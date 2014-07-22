nobone = require 'nobone'
Q = require 'q'
_ = require 'lodash'

{ kit, service: srv } = nobone()

t = Date.now()

create_db_file = ->
	db_file = kit.fs.createWriteStream 'post.db'

	kit.readdir 'post'
	.done (ids) ->
		list = []
		len = ids.length
		kit.async_limit 100, (i) ->
			return if len == i
			path = 'post/' + ids[i]
			kit.readFile path, 'utf8'
			.then (str) ->
				str + '\n'
		, false
		.progress (ret) ->
			list.push ret
			if list.length > 100
				db_file.write list.join('')
				list = []
		.done ->
			db_file.end()
			kit.log Date.now() - t

search = ->
	db = []
	count = 0
	readline = require 'readline'
	db_file = kit.fs.createReadStream 'post.db', 'utf8'

	rl = readline.createInterface {
		input: db_file
		output: process.stdout
		terminal: false
	}

	rl.on 'line', (line) ->
		post = JSON.parse line
		post.tags = post.tags.split ' '
		delete post.frames_pending_string
		delete post.frames_pending
		delete post.frames_string
		delete post.frames
		db.push post

	rl.on 'close', ->
		kit.log Date.now() - t

		srv.get '/', (req, res, next) ->
			if not req.query.s
				next()
				return

			qs = req.query.s.split ','
			rets = _.filter db, (el) ->
				for tag in qs
					if el.tags.indexOf(tag) == -1
						return false
				return true

			res.send rets

		srv.listen 8013

search()
