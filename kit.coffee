nobone = require 'nobone'
Q = require 'q'
_ = require 'lodash'

{ kit, service: srv } = nobone()

t = Date.now()

create_db_file = ->
	db_file = kit.fs.createWriteStream 'yande.post.db'

	kit.readdir 'post'
	.done (ids) ->
		ids.sort (a, b) -> b - a
		list = []
		len = ids.length
		kit.async_limit 100, (i) ->
			return if len == i
			path = 'post/' + ids[i]
			kit.readFile path, 'utf8'
		, false
		.progress (ret) ->
			try
				post = JSON.parse(ret)
				if not _.isArray post.tags
					post.tags = post.tags.split ' '
				list.push JSON.stringify {
					id: post.id
					tags: post.tags
					score: post.score
					author: post.author
					created_at: post.created_at
					width: post.width
					height: post.height
				}
			catch err
				kit.log ret

			if list.length > 100
				process.stdout.write '.'
				db_file.write list.join('\n') + '\n'
				list = []
		.done ->
			db_file.end()
			kit.log Date.now() - t

create_db_file()
