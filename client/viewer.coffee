
$img_list_view = $('.img_list_view')

page_num = location.pathname.match(/\d+$/) or 0

$(window).scrollTop 0

page_indicators = []

is_loading = false

get_param = (name) ->
	name = name.replace(/[\[]/, "\\[").replace(/[\]]/, "\\]")
	regex = new RegExp("[\\?&]" + name + "=([^&#]*)")
	results = regex.exec(location.search)
	if results == null
		null
	else
		decodeURIComponent(results[1].replace(/\+/g, " "))

load_img = ($cols, id) ->
	defer = Q.defer()
	$img = $("
		<img title='#{id}' src='/image/#{id}'>
	")

	$col = _.min $cols, ($col) ->
		$col.height()
	$col.append $img

	$img.error ->
		defer.resolve $img
		$img.remove()
	$img.on 'load', ->
		defer.resolve $img

	defer.promise

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

		$cols = []
		col_num = get_param('col') or 4
		for i in [0...col_num]
			$col = $("<div class='col' style='width: #{100 / col_num}%'></div>")
			$img_list_view.append $col
			$cols.push $col

		tasks = page.map (id) -> -> load_img($cols, id)

		load = (tasks) ->
			task = tasks.shift()
			if task
				task().then ->
					load tasks
			else
				console.log '>> Page loaded.'

		page.reduce (p, id) ->
			p.then ->
				load_img($cols, id)
		, Q()
		.done()

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


$img_list_view.on 'click', 'img', (e) ->
	$this = $(this)

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

	$('#img-show')
	.fadeIn 'fast'
	.prepend $this.clone().width($this[0].naturalWidth)

$('#img-show').on 'click', (e) ->
	if not $.contains $('#post-info')[0], e.target
		$('#img-show')
		.fadeOut 'fast', ->
			$('#img-show')
			.find('img').remove()
		.scrollTop 0
