###
	Use nobone cli tool to execute it.
	I use it to download all the thumb of the site.
	Don't be Evil!
###

nobone = require 'nobone'
{ kit, db, proxy, service, renderer } = nobone {
	db: {
		db_path: 'yande.db'
	}
	proxy: {}
	service: {}
	renderer: {}
}

Q = require 'q'
_ = require 'lodash'
conf = require './conf'
task_list = []

class Get_page

	@all_done: false
	@page_num: 0

	constructor: (work) ->
		self = @

		work.start()

		target = {
			protocol: 'https'
			host: 'yande.re'
			pathname: 'post.json'
			query:
				tags: conf.tags
				page: ++Get_page.page_num
				limit: 50
		}

		target_url = kit.url.format(target)

		kit.request {
			url: target_url
			agent: conf.agent
		}
		.then (body) ->
			list = JSON.parse(body)

			if list.length == 0
				work.stop_timer()
				return

			# Save post list to disk.
			Q.all list.map (post) ->
				path = kit.path.join 'post', post.id + ''
				kit.exists path
				.then (exists) ->
					if exists
						if conf.mode == 'diff'
							work.stop_timer()
					else
						kit.outputFile path, JSON.stringify(post)
			.then ->
				list
		.then (list) ->
			return if not list

			kit.log 'Page: '.cyan + "#{list.length} " + decodeURIComponent(target_url)

			db.exec {
				num: Get_page.page_num
				list: list.map((el) -> el.id)
			}, (jdb, data) ->
				jdb.doc.page_num = data.num
				jdb.doc.post_list = jdb.doc.post_list.concat data.list
				jdb.save()
		.catch (err) ->
			kit.log err
			db.exec {
				url: target_url
				err: err.stack
			}, (jdb, data) ->
				jdb.doc.err_pages[data.url] = data.err
				jdb.save()
		.fin ->
			work.done self

			if work.is_all_done()
				Get_page.all_done = true

class Download_url

	@last_download: null

	constructor: (work) ->
		self = @

		work.start()

		db.exec (jdb) ->
			jdb.save jdb.doc.post_list.shift()
		.then (id) ->
			if not id
				if Get_page.all_done and work.count == 0
					work.stop_timer()
					kit.log "All done.".green
					exit()
				return

			kit.log 'Download: '.cyan + id

			self.id = id

			post_path = kit.path.join 'post', id + ''
			kit.readFile post_path, 'utf8'
			.then (data) ->
				post = JSON.parse data
		.then (post) ->
			return if not post

			url = post[conf.url_key]

			dir = kit.path.join conf.url_key, kit.pad(Math.floor(post.id / 1000), 4)
			path = kit.path.join dir, post.id + kit.path.extname(post.file_url)

			kit.exists (dir)
			.then (exists) ->
				if not exists
					kit.mkdirs dir
			.then ->
				kit.request {
					url: url
					res_pipe: kit.fs.createWriteStream path
					agent: conf.agent
				}
			.catch (err) ->
				kit.log err
				db.exec {
					id: post.id
					err: err.stack
				}, (jdb, data) ->
					jdb.doc.err_posts[data.id] = data.err
					jdb.doc.post_list.push data.id
					jdb.save()
			.then ->
				Download_url.last_download = path
				db.exec (jdb) ->
					jdb.doc.download_count++
					jdb.save()
				kit.log 'Url done: '.cyan + [post.id, post.tags].join(' ')[...120]
		.fin ->
			work.done self

init_basic = ->
	if conf.proxy
		conf.proxy = conf.proxy.split ":"
		conf.agent = proxy.tunnel.httpsOverHttp {
			proxy: {
				host: conf.proxy[0]
				port: conf.proxy[1]
			}
		}

	db.exec conf, (jdb, conf) ->
		jdb.doc.post_list ?= []
		jdb.doc.err_pages ?= {}
		jdb.doc.err_posts ?= {}
		jdb.doc.download_count ?= 0
		jdb.doc.duration ?= 0
		jdb.doc.page_num ?= 0
		jdb.save()

	db.exec (jdb) ->
		Get_page.page_num = jdb.doc.page_num

# Monitor design mode.
monitor = (task, max_tasks = 10) ->
	count = 0
	is_all_done = false

	work = {
		start: ->
			++count
		done: (ref) ->
			--count
			_.remove task_list, (el) -> ref == el
		stop_timer: ->
			is_all_done = true
			clearInterval timer
			kit.log 'Timer stopped.'.yellow
		is_all_done: ->
			is_all_done and count == 0
	}

	timer = setInterval ->
		if count > max_tasks
			return
		work.count = count
		task_list.push(new task(work))
	, 10

auto_update_duration = ->
	# Calc the download duration.
	last_time = Date.now()
	setInterval ->
		now = Date.now()
		span = now - last_time
		db.exec span, (jdb, span) ->
			jdb.doc.duration += span
			jdb.save()
		last_time = now
	, 500

exit = (code = 0) ->
	ids = task_list.map (el) -> el.id

	db.exec ids, (jdb, ids) ->
		for id in ids
			jdb.doc.post_list.unshift id
		jdb.save()
	.done ->
		kit.log "#{ids.length} tasks reverted."
		kit.log 'Compact DB...'
		db.compact_db_file_sync()

		process.exit code

init_web = ->
	service.get '/', (req, res) ->
		renderer.render 'index.ejs'
		.done (tpl) ->
			res.send tpl({
				conf
				nobone: nobone.client()
			})

	service.get '/stats', (req, res) ->
		db.exec (jdb) ->
			jdb.send {
				left: jdb.doc.post_list[0]
				tasks: jdb.doc.post_list.length
				working_tasks: task_list.length
				page_num: jdb.doc.page_num
				download_count: jdb.doc.download_count
				duration: jdb.doc.duration
				err_count: _.keys(jdb.doc.err_pages).length + _.keys(jdb.doc.err_posts).length
			}
		.then (data) ->
			res.send data

	service.get '/last_download', (req, res) ->
		if Download_url.last_download
			res.sendfile Download_url.last_download
		else
			res.send 404

	service.get '/viewer', (req, res) ->
		renderer.render 'viewer.ejs'
		.done (tpl) ->
			res.send tpl({
				nobone: nobone.client()
			})

	service.use renderer.static('client')

	service.listen 8019, ->
		kit.open 'http://127.0.0.1:8019'

init_err_handlers = ->
	process.on 'SIGINT', exit

	process.on 'uncaughtException', (err) ->
		kit.log err.stack
		exit 1

launch = ->
	init_basic()
	init_err_handlers()

	monitor Get_page, 1
	monitor Download_url
	auto_update_duration()

	init_web()

launch()