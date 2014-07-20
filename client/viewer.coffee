
$img_list_view = $('.img_list_view')

page = location.pathname.match(/\d+$/) or 0

$(window).scrollTop 0

is_loading = false
load_images = ->
	return if is_loading

	console.log '>> load images'

	is_loading = true
	$.get '/page/' + page
	.done (ids) ->
		for id, i in ids
			$img = $("<img src='/image/#{id}'>")
			$img_list_view.append $img
			$img.on 'error', -> $img.remove()

		history.pushState '', 'page ' + page, '/viewer/' + page

		page++

		setTimeout ->
			is_loading = false
		, 500

load_images()

$(window).scroll ->
	scroll_h = $(window).scrollTop() + $(window).height()
	doc_height = $(document).height()
	if doc_height - scroll_h < 200
		load_images()