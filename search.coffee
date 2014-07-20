nobone = require 'nobone'
Q = require 'q'

{ kit } = nobone()

t = Date.now()

kit.readdir 'post'
.done (ids) ->
	list = []
	kit.async_limit 100, ids.map (id) ->
		->
			path = 'post/' + id
			kit.readFile path, 'utf8'
			.then (str) ->
				try
					post = JSON.parse str
				catch
					return
				list.push post
				return 10
	.done ->
		kit.log process.memoryUsage()
		kit.log Date.now() - t