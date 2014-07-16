nobone = require 'nobone'
Q = require 'q'
fs = require 'fs-extra'

{ kit } = nobone()

target = {
	protocol: 'https'
	host: 'yande.re'
	pathname: 'post.json'
	query:
		tags: ['ideolo'].join '+'
		page: 0
}

errlog = 'log/err-' + Date.now() + '.log'

kit.mkdirs('imgs').done()

get_page = (target) ->
	target.query.page++

	target_url = kit.url.format(target)

	kit.request {
		url: target_url
	}
	.catch ->
		errlog.appendFile '[page]' + target_url
	.done (body) ->
		kit.log 'Page: '.cyan + target_url
		list = JSON.parse body

		kit.async_limit(10, list.map (el) -> ->
			img_url = decodeURIComponent el.file_url
			path = 'imgs/' + kit.path.basename(img_url)

			kit.request {
				url: el.jpeg_url
				res_encoding: null
				res_pipe: fs.createWriteStream path
			}
			.catch ->
				errlog.appendFile errlog, '[preview]' + el.jpeg_url
			.then (data) ->
				kit.log 'Image: '.cyan + el.jpeg_url
		).done ->
			get_page target

get_page target