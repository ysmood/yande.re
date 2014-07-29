
$img_list_view = $('.img_list_view')
$img_show = $ '#img-show'
$post_info = $ '#post-info'
$tools = $ '#tools'

$(window).scrollTop 0

page_indicators = []

is_loading = false

parse_query = (qs_str) ->
	qs_str = qs_str.match(/^\??(.*)/)[1]
	qs = {}
	for q in qs_str.split '&'
		s = q.split '='
		continue if _.isEmpty s
		qs[s[0]] = s[1] or ''
	qs

format_query = (qs) ->
	s = []
	for k, v of qs
		continue if _.isEmpty v
		s.push [k, v].join('=')
	'?' + s.join('&')

get_query = (name) ->
	qs = parse_query location.search
	qs[name]

set_query = (name, value) ->
	qs = parse_query location.search
	qs[name] = value
	str = format_query qs
	history.replaceState name, value, location.pathname + str

init_dashbaord = ->
	$ratings = $('#dashboard .ratings')
	$score = $('#dashboard .score')
	$page = $('#dashboard .page')
	$col = $('#dashboard .col')

	$ratings.val get_query('ratings')
	$score.val get_query('score')
	$page.val get_query('page')
	$col.val get_query('col') or 4

init_tag_input = ->
	$tags = $('#dashboard .tags')

	tags = decodeURIComponent(get_query 'tags').split(',')

	$tags.tokenInput '/tags', {
		theme: 'mac'
		preventDuplicates: true
		prePopulate: _.map tags, (el) -> { id: el, name: el }
	}

load_img = ($cols, id) ->
	defer = Q.defer()
	$img = $("
		<img class='img' title='#{id}' src='/image/#{id}'>
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

page_num = get_query('page') or 0
load_images = ->
	return if is_loading

	console.log '>> load images'

	is_loading = true
	$.get '/page/' + page_num + location.search
	.done ({ page, count }) ->
		if page.length == 0
			is_loading = false
			return

		page_indicator = $("<h3 class='page_num' num='#{page_num}'><a href='/'>&lt;&lt;</a> Page: #{page_num}</h3>")
		page_indicators.push page_indicator
		$img_list_view.append page_indicator

		$cols = []
		col_num = get_query('col') or 4
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

init_dashbaord()
load_images()
init_tag_input()

$window = $(window)
$document = $(document)
$window.scroll ->
	scroll_h = $window.scrollTop() + $window.height()
	doc_height = $document.height()
	if doc_height - scroll_h < $window.height() * 0.2
		load_images()

	for indicator in page_indicators
		if -$window.height() * 0.5 < $window.scrollTop() - indicator.offset().top < $window.height() * 0.5
			break if num == indicator.attr 'num'
			num = indicator.attr 'num'
			set_query 'page', num
			break


$img_list_view
.on 'click', '.img', (e) ->
	$this = $(this)

	$.getJSON('/post/' + $this.attr('title')).done (post) ->
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

		$post_info
		.fadeIn('fast')
		.find('table').empty().append $(tr)

	$img_show
	.fadeIn 'fast'
	.prepend $this.clone().width($this[0].naturalWidth)
.on 'mouseenter', '.img', ->
	$this = $(this)
	id = $this.attr 'title'
	pos = $this.offset()
	pos.top -= '24'
	$tools.show().offset pos
	$tools.data 'id', id

	$tools.find('.open').attr 'href', "https://yande.re/post/show/" + id
	$tools.find('.download').attr 'href', '/download/' + id

$img_show.on 'click', (e) ->
	if not $.contains $post_info[0], e.target
		$img_show
		.fadeOut 'fast', ->
			$img_show
			.find('.img').remove()
		.scrollTop 0


set_query('', '')