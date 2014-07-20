
module.exports = {
	# One of these: file_url, preview_url, sample_url, jpeg_url.
	url_key: 'preview_url'

	# Where to save the downloaded file.
	img_dir: 'preview'

	# search filter, for example 'rating:safe kantoku'.
	tags: ''

	# Where to save the post info. They are all in json format.
	post_dir: 'post'

	# For example, if you're using goagent on port '8087',
	# you can set it with '127.0.0.1:8078'
	proxy: null

	# By default, download all
	# `diff` mode will try to download the newly added posts.
	mode: 'all'
}
