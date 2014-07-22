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
		, false
		.progress (ret) ->
			post = JSON.parse(ret)
			list.push JSON.stringify {
				id: post.id
				tags: post.tags.split ' '
				score: post.score
				author: post.author
				created_at: post.created_at
				width: post.width
				height: post.height
			}

			if list.length > 100
				process.stdout.write '.'
				db_file.write list.join('\n') + '\n'
				list = []
		.done ->
			db_file.end()
			kit.log Date.now() - t

search = ->
	post_list = []
	readline = require 'readline'
	db_file = kit.fs.createReadStream 'post.db', 'utf8'

	rl = readline.createInterface {
		input: db_file
		output: process.stdout
		terminal: false
	}

	line_count = 0
	rl.on 'line', (line) ->
		post = JSON.parse line
		post_list.push post

	rl.on 'close', ->
		srv.get '/', (req, res, next) ->
			if not req.query.s
				next()
				return

			qs = req.query.s.split ','
			rets = _.filter post_list, (el) ->
				for tag in qs
					if el.tags.indexOf(tag) == -1
						return false
				return true

			res.send rets

		srv.listen 8013

create_db_file()
# search()
