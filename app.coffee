###
	Use nobone cli tool to execute it.
	I use it to download all the thumb of the site.
	Don't be Evil!
###

nobone = require 'nobone'
Q = require 'q'

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

{ kit, db, proxy } = nobone {
	db: {
		db_path: 'yande.db'
	}
	proxy: {}
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
	jdb.doc.post_done ?= []
	jdb.doc.err_pages = {}
	jdb.doc.err_imgs = {}
	jdb.save()

# Monitor design mode.
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
		if count >= max_tasks
			return
		work.count = count
		task work
	, 10

page_num = 0
db.exec (jdb) ->
	page_num = jdb.doc.page_num or 0

get_page_done = false
get_page = (work) ->
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

	work.start()

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
			kit.outputFile path, JSON.stringify(post)
		.then ->
			list
	.catch (err) ->
		db.exec {
			url: target_url
			err: err.toString()
		}, (jdb, data) ->
			jdb.doc.err_pages[data.url] = data.err
			jdb.save()
	.done (list) ->
		return if not list

		kit.log 'Page: '.cyan + " #{list.length} " + decodeURIComponent(target_url)

		work.done()

		if work.is_all_done()
			get_page_done = true

		db.exec {
			num: page_num
			list: list.map((el) -> el.id)
		}, (jdb, data) ->
			jdb.doc.page_num = data.num
			jdb.doc.post_list = jdb.doc.post_list.concat data.list
			jdb.save()

download_url = (work) ->
	db.exec (jdb) ->
		jdb.save jdb.doc.post_list.shift()
	.then (id) ->
		return if not id

		kit.log 'Download: '.cyan + id

		db.exec (jdb) ->
			if jdb.doc.post_done.indexOf(id)
				jdb.send null
			else
				jdb.send id
	.then (id) ->
		if not id
			if get_page_done and work.count == 0
				work.stop_timer()
				kit.log "All done.".green
				exit()
			return

		work.start()

		post_path = kit.path.join conf.post_dir, id + ''
		kit.readFile post_path, 'utf8'
		.then (data) ->
			post = JSON.parse data
	.then (post) ->
		return if not post

		url = post[conf.url_key]

		path = conf.img_dir + '/' + kit.path.basename(decodeURIComponent url)
		kit.request {
			url: url
			res_pipe: kit.fs.createWriteStream path
			agent: conf.agent
		}
		.catch (err) ->
			db.exec  {
				url
				err: err.toString()
			}, (jdb, data) ->
				jdb.doc.err_imgs[data.url] = data.err
				jdb.save()
		.then ->
			kit.log 'Url done: '.cyan + [post.id, post.tags].join(' ')
			post
	.done (post) ->
		return if not post

		work.done()
		db.exec post.id, (jdb, id) ->
			jdb.doc.post_done.push id
			jdb.save()

exit = (code = 0) ->
	kit.log 'Compact DB...'
	db.compact_db_file_sync()
	process.exit code

process.on 'SIGINT', exit

process.on 'uncaughtException', (err) ->
	kit.err err
	code 1

monitor get_page, 1
monitor download_url