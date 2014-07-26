# process.env.NODE_ENV = 'development'

module.exports = {

	port: 8019

	# One of these: file_url, preview_url, sample_url, jpeg_url.
	url_key: 'sample_url'

	# search filter, for example 'rating:safe kantoku'.
	tags: ''

	# For example, if you're using goagent on port '8087',
	# you can set it with '127.0.0.1:8078'
	proxy: null

	# `default` by default, download all.
	# `diff` mode will try to download the newly added posts.
	# `err` mode will try to download all the errored url.
	# `view` mode will try to download all the errored url.
	mode: 'default'

	# Automatically open the monitor page.
	auto_open_page: true
}
