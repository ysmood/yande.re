###
	Use nobone cli tool to execute it.
	I use it to download all the thumb of the site.
	Don't be Evil!
###

Q = require 'q'
_ = require 'lodash'
default_conf = require './conf.default'
conf = _.defaults require('./conf'), default_conf
task_list = []

nobone = require 'nobone'
{ kit, db, proxy, service, renderer } = nobone {
	db: {
		db_path: 'yande.db'
	}
	proxy: {}
	service: {}
	renderer: {}
}

class Page_worker

	@all_done: false

	constructor: (work) ->
		self = @

		download = (url) ->
			Q.fcall ->
				return if not url

				kit.request {
					url
					agent: conf.agent
					redirect: 3
				}
			.then (body) ->
				return if not body

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
					num: Page_worker.page_num
					list: list.map((el) -> el.id)
				}, (jdb, data) ->
					jdb.doc.page_num = data.num
					for el in data.list
						jdb.doc.post_list.push el if jdb.doc.post_list.indexOf(el) == -1
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
					Page_worker.all_done = true
					kit.log 'Pages Done'.yellow

		Page_worker.url_iter().done download

	@url_iter: ->
		db.exec (jdb) ->
			jdb.send jdb.doc.post_list.length > 1000
		.then (too_many_tasks) ->
			return if too_many_tasks

			if conf.mode == 'err'
				db.exec (jdb) ->
					url = jdb.doc.err_page_urls.shift()
					jdb.save url
			else
				kit.url.format {
					protocol: 'https'
					host: 'yande.re'
					pathname: 'post.json'
					query:
						tags: conf.tags
						page: ++Page_worker.page_num
						limit: 50
				}

class File_worker

	@last_download: null

	constructor: (work) ->
		self = @

		db.exec (jdb) ->
			jdb.save jdb.doc.post_list.shift()
		.then (id) ->
			if not id
				if Page_worker.all_done and work.count == 0
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
				kit.log 'Download: '.cyan + url
				f_stream = kit.fs.createWriteStream path
				kit.request {
					url: url
					res_pipe: f_stream
					redirect: 3
					agent: conf.agent
				}
			.then ->
				File_worker.last_download = post.id
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
		Page_worker.page_num = jdb.doc.page_num

		jdb.doc.err_page_urls = []
		for k, v of jdb.doc.err_pages
			jdb.doc.err_page_urls.push k

	if conf.mode == 'diff'
		Page_worker.page_num = 0

# Monitor design mode.
monitor = (task, max_tasks = 10, span = 100) ->
	count = 0
	is_all_done = false

	run = ->
		n = max_tasks - count
		_.times n, ->
			task_list.push(new task({
				count: count++
				done: (ref) ->
					count--
					_.remove task_list, (el) -> ref == el
				stop_timer: ->
					is_all_done = true
					clearInterval timer
					kit.log 'Timer stopped:'.yellow
				is_all_done: ->
					is_all_done and count == 0
			}))

	run()

	timer = setInterval run, span

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
	if exit.is_exited
		return
	exit.is_exited = true

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

binary_search = (arr, ele) ->
	beginning = 0
	end = arr.length
	target = null
	while true
		target = ((beginning + end) >> 1);
		if ((target == end || target == beginning) && arr[target] != ele)
			return -1;

		if arr[target] > ele
			end = target
		else if arr[target] < ele
			beginning = target
		else
			return target

init_web = ->
	service.get '/monitor', (req, res) ->
		renderer.render 'ejs/index.ejs'
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
				last_download: File_worker.last_download
			}
		.then (data) ->
			res.send data

	service.get '/reload_post_db', (req, res) ->
		reload_post_db().done ->
			res.status(200).end()

	service.get '/unload_post_db', (req, res) ->
		db.posts = []
		res.status(200).end()

	service.get '/post/:id', (req, res) ->
		res.sendfile 'post/' + req.params.id

	service.get '/image/:id', (req, res) ->
		id = req.params.id
		kit.readFile 'post/' + id, 'utf8'
		.catch (err) ->
			res.status(404).end()
		.done (str) ->
			post = JSON.parse str
			dir = kit.path.join conf.url_key, kit.pad(Math.floor(post.id / 1000), 4)
			path = kit.path.join dir, post.id + kit.path.extname(post.file_url)
			res.sendfile path

	service.get '/download/:id', (req, res) ->
		id = req.params.id
		kit.readFile 'post/' + id
		.catch ->
			res.status(500).end()
		.done (str) ->
			post = JSON.parse str
			res.status 301
			res.redirect post.jpeg_url

	viewer = (req, res) ->
		renderer.render 'ejs/viewer.ejs'
		.done (tpl) ->
			res.send tpl()

	service.get '/', viewer

	service.get '/tags', (req, res) ->
		ret = []
		limit = 50
		if req.query.q
			query = req.query.q
			for tag, i in db.tags
				if tag.indexOf(query) == 0
					ret.push { id: tag, name: tag }
					if ret.length == limit
						break
		res.send ret

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
		_.each db.posts, (el) ->
			if el.score < score
				return
			if ratings.indexOf(el.rating) == -1
				return
			if _.isArray tags
				for tag in tags
					if el.tags.indexOf(tag) == -1
						return
			ids.push el.id

		num = +req.params.num * 50
		page = ids[num ... num + 50]
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

	db.posts = []
	db.tags = []

	rl = readline.createInterface {
		input: db_file
		output: process.stdout
		terminal: false
	}

	line_count = 0
	rl.on 'line', (line) ->
		try
			post = JSON.parse line
			db.posts.push post

			for tag in post.tags
				if db.tags[tag] == undefined
					db.tags[tag] = 0
				else
					db.tags[tag]++
		catch err
			kit.log err

	rl.on 'close', ->
		db.posts.sort (a, b) -> b.id - a.id
		_.uniq db.posts, true, 'id'

		db.tags = _.map(
			_.pairs(db.tags).sort((a, b) -> b[1] - a[1])
			(el) -> el[0]
		)

		kit.log 'Post db loaded: '.yellow + db.posts.length
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
			monitor Page_worker, conf.page_worker_num
			monitor File_worker, conf.file_worker_num
			auto_update_duration()

		init_web()
		reload_post_db()


launch()