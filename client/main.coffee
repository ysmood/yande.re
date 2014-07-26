$ = (sel, el = document) ->
	document.querySelectorAll.call el, sel

get = (path, callback) ->
	xhr = new XMLHttpRequest
	xhr.open 'GET', path
	xhr.addEventListener 'readystatechange', ->
		if xhr.readyState != 4
			return

		callback xhr.responseText

	xhr.send()

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
	get '/stats', (data) ->
		data = JSON.parse data
		$('.left')[0].textContent = data.left
		$('.tasks')[0].textContent = data.tasks
		$('.working_tasks')[0].textContent = data.working_tasks
		ratio = data.download_count * 100 / (data.download_count + data.left)
		$('.download_count')[0].textContent = data.download_count + ", #{ratio.toFixed(2)}%"
		$('.duration')[0].textContent = format_time data.duration
		$('.page')[0].textContent = data.page_num
		$('.err')[0].textContent = data.err_count
		$('.mem_usage')[0].textContent = (data.mem_usage.rss / 1024 / 1024).toFixed(2) + ' MB'
		$('.last_download')[0].textContent = data.err_count
		$('.last_download')[0].src = '/image/' + data.last_download

auto_update = ->
	set_state()
	setInterval set_state, 1000

auto_update()

$('.reload_post_db')[0].addEventListener 'click', ->
	self = @
	self.disabled = true
	get '/reload_post_db', ->
		self.disabled = false
		alert 'Post Database Reloaded.'