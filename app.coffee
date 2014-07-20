###
	Use nobone cli tool to execute it.
	I use it to download all the thumb of the site.
	Don't be Evil!
###

nobone = require 'nobone'
Q = require 'q'
_ = require 'lodash'

conf = {
	# One of these: file_url, preview_url, sample_url, jpeg_url.
	url_key: 'preview_url'

	# Where to save the downloaded file.
	img_dir: 'preview'

	# search filter, for example 'rating:safe kantoku'.
	tags: ''

	# Where to save the post info. They are all in json format.
	post_dir: 'post'

	# For example, if you're using goagent on port '8087',
	# you can set it with '127.0.0.1:8078'
	proxy: null
}

{ kit, db, proxy, service, renderer } = nobone {
	db: {
		db_path: 'yande.db'
	}
	proxy: {}
	service: {}
	renderer: {}
}

if conf.proxy
	conf.proxy = conf.proxy.split ":"
	conf.agent = proxy.tunnel.httpsOverHttp {
		proxy: {
			host: conf.proxy[0]
			port: conf.proxy[1]
		}
	}

kit.mkdirs(conf.img_dir).done()
kit.mkdirs(conf.post_dir).done()

db.exec conf, (jdb, conf) ->
	jdb.doc.post_list ?= []
	jdb.doc.err_pages ?= {}
	jdb.doc.err_posts ?= {}
	jdb.doc.download_count ?= 0
	jdb.doc.page_num ?= 0
	jdb.save()

# Monitor design mode.
work_list = []
monitor = (task, max_tasks = 10) ->
	count = 0
	is_all_done = false

	work = {
		start: ->
			++count
		done: ->
			--count
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
		task work
	, 10

	work_list.push work

page_num = 0
db.exec (jdb) ->
	page_num = jdb.doc.page_num

get_page_done = false
get_page = (work) ->
	work.start()

	target = {
		protocol: 'https'
		host: 'yande.re'
		pathname: 'post.json'
		query:
			tags: conf.tags
			page: ++page_num
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
			path = kit.path.join conf.post_dir, post.id + ''
			kit.exists path
			.then (exists) ->
				if not exists
					kit.outputFile path, JSON.stringify(post)
		.then ->
			list
	.then (list) ->
		return if not list

		kit.log 'Page: '.cyan + "#{list.length} " + decodeURIComponent(target_url)

		db.exec {
			num: page_num
			list: list.map((el) -> el.id)
		}, (jdb, data) ->
			jdb.doc.page_num = data.num
			jdb.doc.post_list = jdb.doc.post_list.concat data.list
			jdb.save()
	.catch (err) ->
		kit.err err
		db.exec {
			url: target_url
			err: err.stack
		}, (jdb, data) ->
			jdb.doc.err_pages[data.url] = data.err
			jdb.save()
	.fin ->
		work.done()

		if work.is_all_done()
			get_page_done = true

download_url = (work) ->
	work.start()

	db.exec (jdb) ->
		jdb.save jdb.doc.post_list.shift()
	.then (id) ->
		if not id
			if get_page_done and work.count == 0
				work.stop_timer()
				kit.log "All done.".green
				exit()
			return

		kit.log 'Download: '.cyan + id

		post_path = kit.path.join conf.post_dir, id + ''
		kit.readFile post_path, 'utf8'
		.then (data) ->
			post = JSON.parse data
	.then (post) ->
		return if not post

		url = post[conf.url_key]

		path = conf.img_dir + '/' + kit.path.basename(decodeURIComponent post.file_url).replace('yande.re ', '')
		kit.request {
			url: url
			res_pipe: kit.fs.createWriteStream path
			agent: conf.agent
		}
		.catch (err) ->
			kit.err err
			db.exec {
				id: post.id
				err: err.stack
			}, (jdb, data) ->
				jdb.doc.err_posts[data.id] = data.err
				jdb.doc.post_list.push data.id
				jdb.save()
		.then ->
			db.exec (jdb) ->
				jdb.doc.download_count++
				jdb.save()
			kit.log 'Url done: '.cyan + [post.id, post.tags].join(' ')[...120]
	.fin ->
		work.done()

exit = (code = 0) ->
	kit.log 'Compact DB...'
	db.compact_db_file_sync()
	process.exit code

process.on 'SIGINT', exit

process.on 'uncaughtException', (err) ->
	kit.err err.stack
	process.exit 1

monitor get_page, 1
monitor download_url

service.get '/', (req, res) ->
	renderer.render 'index.ejs'
	.done (tpl) ->
		res.send tpl({
			nobone: nobone.client()
		})

service.get '/stats', (req, res) ->
	db.exec (jdb) ->
		jdb.send {
			left: jdb.doc.post_list[0]
			tasks: jdb.doc.post_list.length
			working_tasks: work_list.reduce ((sum, el) -> sum += el.count), 0
			page_num: jdb.doc.page_num
			download_count: jdb.doc.download_count
			err_count: _.keys(jdb.doc.err_pages).length + _.keys(jdb.doc.err_posts).length
		}
	.then (data) ->
		res.send data

service.use renderer.static('client')

service.listen 8019, ->
	kit.open 'http://127.0.0.1:8019'
