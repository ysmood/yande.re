
$img_list_view = $('.img_list_view')

page_num = location.pathname.match(/\d+$/) or 0

$(window).scrollTop 0

page_indicators = []

is_loading = false
load_images = ->
	return if is_loading

	console.log '>> load images'

	is_loading = true
	$.get '/page/' + page_num + location.search
	.done ({ page, count }) ->
		if page.length == 0
			is_loading = false
			return

		page_indicator = $("<h3 class='page_num' num='#{page_num}'>Page: #{page_num}</h3>")
		page_indicators.push page_indicator
		$img_list_view.append page_indicator
		for id, i in page
			$img = $("
				<img title='#{id}' src='/image/#{id}'>
			")
			$img_list_view.append $img
			$img.on 'error', -> $img.remove()

		page_num++

		setTimeout ->
			is_loading = false
		, 500

load_images()

$window = $(window)
$document = $(document)
num = 0
$window.scroll ->
	scroll_h = $window.scrollTop() + $window.height()
	doc_height = $document.height()
	if doc_height - scroll_h < $window.height() * 0.2
		load_images()

	for indicator in page_indicators
		if -$window.height() * 0.5 < $window.scrollTop() - indicator.offset().top < $window.height() * 0.5
			break if num == indicator.attr 'num'
			num = indicator.attr 'num'
			history.replaceState num, 'page ' + num, '/viewer/' + num + location.search
			break


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

