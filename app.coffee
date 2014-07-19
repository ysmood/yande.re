nobone = require 'nobone'
Q = require 'q'

conf =
	img_dir: 'preview'
	url_key: 'preview_url'
	tags: ''
	post_dir: 'post'

{ kit, db } = nobone {
	db: {
		db_path: 'yande.db'
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
		is_all_done: ->
			is_all_done and count == 0
	}

	timer = setInterval ->
		if count >= max_tasks
			return
		work.count = count
		task work
	, 30

get_page_done = false
page_num = 0

db.exec (jdb) ->
	jdb.send jdb.doc.page_num
.done (num) ->
	page_num = num or 0

get_page = (work) ->
	page_num ?= 0
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
	}
	.catch (err) ->
		db.exec {
			url: target_url
			err: err.toString()
		}, (jdb, data) ->
			jdb.doc.err_pages[data.url] = data.err
			jdb.save()
	.then (body) ->
		kit.log 'Page: '.cyan + decodeURIComponent(target_url)
		list = JSON.parse(body)

		if list.length == 0
			work.stop_timer()
			return

		# Save post list to disk.
		Q.all list.map (post) ->
			path = kit.path.join conf.post_dir, post.id
			kit.outputFile path, JSON.stringify(post)
		.then ->
			list
	.done (list) ->
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
	Q.fcall ->
		db.exec (jdb) ->
			jdb.send [
				jdb.doc.post_list
				jdb.doc.post_done
			]
	.then ([post_list, post_done]) ->
		if post_list.length == 0
			if get_page_done and work.count == 0
				work.stop_timer()
				db.compact_db_file()
				kit.log "All done.".green
			return

		id = post_list.shift()
		return if post_done.indexOf(id) > -1

		work.start()

		post_path = kit.path.join conf.post_dir, id
		kit.readFile post_path, 'utf8'
	.then (data) ->
		return if not data

		post = JSON.parse data

		url = post[conf.url_key]

		kit.log 'Download: '.cyan + decodeURIComponent(url)

		path = conf.img_dir + '/' + kit.path.basename(decodeURIComponent url)
		kit.request {
			url: url
			res_pipe: kit.fs.createWriteStream path
		}
	.catch (err) ->
		db.exec  {
			url
			err: err.toString()
		}, (jdb, data) ->
			jdb.doc.err_imgs[data.url] = data.err
			jdb.save()
	.done ->
		work.done()
		kit.log 'Image: '.cyan + decodeURIComponent(url)

		db.exec post.id, (jdb, id) ->
			jdb.doc.post_done.push id
			jdb.save()

monitor get_page, 1
monitor download_url