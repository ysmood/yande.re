
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
			$img = $("
				<img title='#{id}' src='/image/#{id}'>
			")
			$img_list_view.append $img
			$img.on 'error', -> $img.remove()

		history.pushState '', 'page ' + page, '/viewer/' + page

		page++

		setTimeout ->
			is_loading = false
		, 500

load_images()

$window = $(window)
$document = $(document)
$window.scroll ->
	scroll_h = $window.scrollTop() + $window.height()
	doc_height = $document.height()
	if doc_height - scroll_h < 200
		load_images()

$img_list_view.on 'click', (e) ->
	$this = $(e.target)

	if $this.is 'img'
		$.get('/post/' + $this.attr('title')).done (post) ->
			if typeof post == 'string'
				post = JSON.parse post

			tr = ''
			for k, v of post
				if k == 'id'
					v = "<a href='https://yande.re/post/show/#{v}' target='_blank'>#{v}</a>"
				tr += "
					<tr>
						<td>#{k}</td>
						<td>#{v}</td>
					</tr>
				"

			$('#post-info')
			.fadeIn('fast')
			.find('table').empty().append $(tr)
	else if $('#post-info').is ':visible'
		$('#post-info').fadeOut()

