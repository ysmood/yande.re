nobone = require 'nobone'
Q = require 'q'
fs = require 'fs-extra'

conf =
	img_dir: 'preview'
	url_key: 'preview_url'
	tags: ''

{ kit, db } = nobone {
	db: {
		db_path: 'yande.db'
	}
}

kit.mkdirs(conf.img_dir).done()

db.exec conf, (jdb, conf) ->
	jdb.doc.post_list = []
	jdb.doc.post_done ?= []
	jdb.doc.err_pages = {}
	jdb.doc.err_imgs = {}
	jdb.save()

# Monitor design mode.
monitor = (task) ->
	count = 0
	max_tasks = 10
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
get_page = (work) ->
	work.page_num ?= 1
	target = {
		protocol: 'https'
		host: 'yande.re'
		pathname: 'post.json'
		query:
			tags: conf.tags
			page: work.page_num++
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
	.done (body) ->
		kit.log 'Page: '.cyan + decodeURIComponent(target_url)
		list = JSON.parse(body)

		work.done()

		if work.is_all_done()
			get_page_done = true

		if list.length == 0
			work.stop_timer()
			return

		db.exec list, (jdb, list) ->
			jdb.doc.post_list = jdb.doc.post_list.concat list

download_url = (work) ->
	db.exec (jdb) ->
		jdb.send [
			jdb.doc.post_list
			jdb.doc.post_done
		]
	.done ([post_list, post_done]) ->
		if post_list.length == 0
			if get_page_done and work.count == 0
				work.stop_timer()
				db.compact_db_file()
				kit.log "All done.".green
			return

		post = post_list.shift()
		url = post[conf.url_key]

		return if post_done.indexOf(post.id) > -1

		kit.log 'Download: '.cyan + decodeURIComponent(url)

		path = conf.img_dir + '/' + kit.path.basename(decodeURIComponent url)
		kit.request {
			url: url
			res_pipe: fs.createWriteStream path
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

		work.start()

monitor get_page
monitor download_url