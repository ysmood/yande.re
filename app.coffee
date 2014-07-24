###
	Use nobone cli tool to execute it.
	I use it to download all the thumb of the site.
	Don't be Evil!
###

Q = require 'q'
_ = require 'lodash'
conf = require './conf'
task_list = []
post_db = []

nobone = require 'nobone'
{ kit, db, proxy, service, renderer } = nobone {
	db: {
		db_path: 'yande.db'
	}
	proxy: {}
	service: {}
	renderer: {}
}

class Get_page

	@all_done: false

	constructor: (work) ->
		self = @

		work.start()

		download = (url) ->
			Q.fcall ->
				return if not url

				kit.request {
					url
					agent: conf.agent
				}
			.then (body) ->
				if not body
					work.stop_timer()
					return

				list = JSON.parse(body)

				if list.length == 0
					work.stop_timer()
					return

				# Save post list to disk.
				nothing_new = false
				exists_count = 0
				Q.all list.map (post) ->
					path = kit.path.join 'post', post.id + ''
					kit.exists path
					.then (exists) ->
						if exists
							if ++exists_count == list.length and
							conf.mode == 'diff'
								work.stop_timer()
								nothing_new = true
						else
							kit.appendFile 'yande.post.db', JSON.stringify({
									id: post.id
									tags: post.tags.split ' '
									score: post.score
									rating: post.rating
									author: post.author
									created_at: post.created_at
									width: post.width
									height: post.height
								}) + '\n'
							.then ->
								kit.outputFile path, JSON.stringify(post) + '\n'
				.then ->
					if nothing_new
						kit.log 'Nothing new.'.cyan
						return
					list
			.then (list) ->
				return if not list

				kit.log 'Page: '.cyan + "#{list.length} " + decodeURIComponent(url)

				db.exec {
					url
					num: Get_page.page_num
					list: list.map((el) -> el.id)
				}, (jdb, data) ->
					jdb.doc.page_num = data.num
					jdb.doc.post_list = jdb.doc.post_list.concat data.list
					delete jdb.doc.err_pages[data.url]
					jdb.save()
			.catch (err) ->
				kit.log err
				db.exec {
					url
					err: err.stack
				}, (jdb, data) ->
					jdb.doc.err_pages[data.url] = data.err
					jdb.save()
			.fin ->
				work.done self

				if work.is_all_done()
					Get_page.all_done = true
					kit.log 'Get_page All_done'.yellow

		Get_page.url_iter().done download

	@url_iter: ->
		if conf.mode == 'err'
			db.exec (jdb) ->
				url = jdb.doc.err_page_urls.shift()
				jdb.save url
		else
			Q kit.url.format {
				protocol: 'https'
				host: 'yande.re'
				pathname: 'post.json'
				query:
					tags: conf.tags
					page: ++Get_page.page_num
					limit: 50
			}

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
					clearInterval auto_update_duration.tmr
					kit.log "All done.".green
				return

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
			f_stream = null

			kit.exists (dir)
			.then (exists) ->
				if not exists
					kit.mkdirs dir
			.then ->
				f_stream = kit.fs.createWriteStream path
				kit.request {
					url: url
					res_pipe: f_stream
					agent: conf.agent
				}
			.then ->
				Download_url.last_download = path
				db.exec (jdb) ->
					jdb.doc.download_count++
					jdb.save()
				# kit.log 'Url done: '.cyan + [post.id, post.tags].join(' ')[...120]
			.catch (err) ->
				f_stream.end()
				kit.log "#{post.id} #{err.message}".red
				db.exec {
					id: post.id
					err: err.stack
				}, (jdb, data) ->
					jdb.doc.err_posts[data.id] = data.err
					jdb.doc.post_list.push data.id
					jdb.save()
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

	# Database
	db.exec conf, (jdb, conf) ->
		jdb.doc.post_list ?= []
		jdb.doc.err_pages ?= {}
		jdb.doc.err_posts = {}
		jdb.doc.download_count ?= 0
		jdb.doc.duration ?= 0
		jdb.doc.page_num ?= 0
		jdb.save()

	db.exec (jdb) ->
		Get_page.page_num = jdb.doc.page_num

		jdb.doc.err_page_urls = []
		for k, v of jdb.doc.err_pages
			jdb.doc.err_page_urls.push k

	if conf.mode == 'diff'
		Get_page.page_num = 0

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
			kit.log 'Timer stopped:'.yellow
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
	auto_update_duration.tmr = setInterval ->
		now = Date.now()
		span = now - last_time
		db.exec span, (jdb, span) ->
			jdb.doc.duration += span
			jdb.save()
		last_time = now
	, 500

exit = (code = 0) ->
	ids = []
	task_list.forEach (el) ->
		ids.push(el.id) if _.has el, 'id'

	db.exec ids, (jdb, ids) ->
		for id in ids
			jdb.doc.post_list.unshift id
		jdb.save()
	.then ->
		kit.log "#{ids.length} tasks reverted."
		kit.log 'Compact DB...'
		db.compact_db_file()
	.catch (err) ->
		kit.log err
	.done ->
		process.exit code

init_web = ->
	service.get '/', (req, res) ->
		renderer.render 'index.ejs'
		.done (tpl) ->
			res.send tpl({
				conf
			})

	service.get '/stats', (req, res) ->
		db.exec (jdb) ->
			jdb.send {
				left: +jdb.doc.post_list[0]
				tasks: jdb.doc.post_list.length
				working_tasks: task_list.length
				page_num: jdb.doc.page_num
				download_count: jdb.doc.download_count
				duration: jdb.doc.duration
				err_count: _.keys(jdb.doc.err_pages).length + _.keys(jdb.doc.err_posts).length
				mem_usage: process.memoryUsage()
			}
		.then (data) ->
			res.send data

	service.get '/reload_post_db', (req, res) ->
		reload_post_db().done ->
			res.send 200

	service.get '/last_download', (req, res) ->
		if Download_url.last_download
			res.sendfile Download_url.last_download
		else
			res.send 404

	service.get '/post/:id', (req, res) ->
		res.sendfile 'post/' + req.params.id

	service.get '/image/:id', (req, res) ->
		id = req.params.id
		kit.readFile 'post/' + id, 'utf8'
		.done (str) ->
			post = JSON.parse str
			dir = kit.path.join conf.url_key, kit.pad(Math.floor(post.id / 1000), 4)
			path = kit.path.join dir, post.id + kit.path.extname(post.file_url)
			res.sendfile path

	service.sse '/download', (req, res) ->
		url = req.query.url
		path = './' + req.query.path

		kit.mkdirs kit.path.dirname(path)
		.then ->
			len = 0
			count = 0
			f_stream = kit.fs.createWriteStream path
			p = kit.request {
				url: url
				res_pipe: f_stream
				agent: conf.agent
			}
			p.req.on 'response', (r) ->
				len = r.headers['content-length']
			p.req.on 'data', (buf) ->
				count += buf.length

			p
		.done ->

	viewer = (req, res) ->
		renderer.render 'viewer.ejs'
		.done (tpl) ->
			res.send tpl()

	service.get '/viewer', viewer
	service.get '/viewer/*', viewer

	service.get '/page/:num', (req, res) ->
		if req.query.tags
			tags = req.query.tags.split ','
		else
			tags = null

		if req.query.score
			score = +req.query.score
		else
			score = 0

		if req.query.ratings
			ratings = req.query.ratings.split ''
		else
			ratings = ['s', 'q', 'e']

		ids = []
		_.each post_db, (el) ->
			if el.score < score
				return
			if ratings.indexOf(el.rating) == -1
				return
			if _.isArray tags
				for tag in tags
					if el.tags.indexOf(tag) == -1
						return
			ids.push el.id

		num = +req.params.num * 100
		page = ids[num ... num + 100]
		res.send {
			page
			count: ids.length
		}

	service.use renderer.static('client')

	kit.log 'Listen port ' + conf.port
	service.listen conf.port, ->
		if conf.auto_open_page
			kit.open 'http://127.0.0.1:' + conf.port

reload_post_db = ->
	if not kit.fs.existsSync 'yande.post.db'
		return

	defer = Q.defer()

	readline = require 'readline'
	db_file = kit.fs.createReadStream 'yande.post.db', 'utf8'

	post_db = []

	rl = readline.createInterface {
		input: db_file
		output: process.stdout
		terminal: false
	}

	line_count = 0
	rl.on 'line', (line) ->
		try
			post = JSON.parse line
			post_db.push post
		catch err
			kit.log err

	rl.on 'close', ->
		post_db.sort (a, b) -> b.id - a.id
		_.uniq post_db, true, 'id'
		kit.log 'Post db loaded: '.yellow + post_db.length
		defer.resolve()

	defer.promise

init_err_handlers = ->
	process.on 'SIGINT', exit

	process.on 'uncaughtException', (err) ->
		kit.log err.stack
		exit 1

launch = ->
	db.loaded.done ->
		init_basic()
		init_err_handlers()

		if conf.mode != 'view'
			monitor Get_page, 1
			monitor Download_url
			auto_update_duration()

		init_web()
		reload_post_db()

		tmr = setInterval ->
			if Get_page.all_done
				clearInterval tmr
				return
			reload_post_db()
		, 1000 * 60 * 20

launch()