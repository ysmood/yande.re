nobone = require 'nobone'
Q = require 'q'
fs = require 'fs-extra'

conf =
	img_dir: 'imgs'
	img_key: 'jpeg_url'

{ kit, db } = nobone {
	db: {
		db_path: 'yande.db'
	}
}

target = {
	protocol: 'https'
	host: 'yande.re'
	pathname: 'post.json'
	query:
		tags: 'ideolo'
		page: 0
}

kit.mkdirs(conf.img_dir).done()

db.exec {
	command: (jdb) ->
		jdb.doc.img_url_list = []
		jdb.doc.img_url_list_done ?= []
		jdb.doc.img_url_done ?= []
		jdb.doc.err_pages = {}
		jdb.doc.err_imgs = {}
		jdb.save()
}

list_done = false
get_page = (target) ->
	target.query.page++

	target_url = kit.url.format(target)

	kit.request {
		url: target_url
	}
	.catch (err) ->
		db.exec {
			data: {
				url: target_url
				err: err.toString()
			}
			command: (jdb, data) ->
				jdb.doc.err_pages[data.url] = data.err
				jdb.save()
		}
	.done (body) ->
		kit.log 'Page: '.cyan + decodeURIComponent(target_url)
		list = JSON.parse(body).map (el) -> el[conf.img_key]

		if list.length == 0
			list_done = true
			return

		db.exec {
			data: list
			command: (jdb, list) ->
				jdb.doc.img_url_list = jdb.doc.img_url_list.concat list

				len = jdb.doc.img_url_list_done.length
				jdb.doc.img_url_list_done = _.union(
					jdb.doc.img_url_list_done
					list
				)

				jdb.save len == jdb.doc.img_url_list_done.length
		}
		.done (nothing_new) ->
			if nothing_new
				list_done = true
				return

			get_page target

working_tasks = 0
max_working_tasks = 10
get_imgs = ->
	db.exec {
		command: (jdb) ->
			jdb.send [
				jdb.doc.img_url_list
				jdb.doc.img_url_done
			]
	}
	.done ([img_url_list, img_url_done]) ->
		if working_tasks > max_working_tasks or
		img_url_list.length == 0
			if list_done and working_tasks == 0
				kit.log "All done.".green
				clearInterval monitor
			return

		img_url = img_url_list.shift()

		return if img_url_done.indexOf(img_url) > -1

		kit.log 'Download: '.cyan + decodeURIComponent(img_url)

		path = conf.img_dir + '/' + kit.path.basename(decodeURIComponent img_url)
		kit.request {
			url: img_url
			res_pipe: fs.createWriteStream path
		}
		.catch (err) ->
			db.exec {
				data: {
					url: target_url
					err: err.toString()
				}
				command: (jdb, data) ->
					jdb.doc.err_imgs[data.url] = data.err
					jdb.save()
			}
		.done ->
			working_tasks--
			kit.log 'Image: '.cyan + decodeURIComponent(img_url)

			db.exec {
				data: img_url
				command: (jdb, img_url) ->
					jdb.doc.img_url_done.push img_url
					jdb.save()
			}

		working_tasks++

get_page target

# Monitor design mode.
monitor = setInterval get_imgs, 30