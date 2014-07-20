$ = (sel, el = document) ->
	document.querySelectorAll.call el, sel

format_time = (stamp) ->
	get_step = (unit) ->
		step = Math.floor(stamp / unit)
		stamp = stamp % unit
		step

	pad = (str, width = 2, char = '0') ->
		str = str + ''
		if str.length >= width
			str
		else
			new Array(width - str.length + 1).join(char) + str

	d = get_step 1000 * 3600 * 24
	h = get_step 1000 * 3600
	m = get_step 1000 * 60
	s = get_step 1000

	d + ' day, ' + [h, m, s].map((el) -> pad el).join ':'

set_state = ->
	xhr = new XMLHttpRequest

	xhr.open 'GET', '/stats'

	xhr.addEventListener 'readystatechange', ->
		if xhr.readyState != 4
			return

		data = JSON.parse xhr.responseText
		$('.left span')[0].textContent = data.left
		$('.tasks span')[0].textContent = data.tasks
		$('.working_tasks span')[0].textContent = data.working_tasks
		$('.download_count span')[0].textContent = data.download_count
		$('.duration span')[0].textContent = format_time data.duration
		$('.page span')[0].textContent = data.page_num
		$('.err span')[0].textContent = data.err_count

	xhr.send()

auto_update = ->
	set_state()
	setInterval set_state, 1000

auto_update()
