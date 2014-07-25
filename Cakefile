{ kit } = require 'nobone'

task 'setup', 'setup', ->
	kit.exists 'conf.coffee'
	.then (exists) ->
		if not exists
			kit.copy 'conf.default.coffee', 'conf.coffee'
	.done()
