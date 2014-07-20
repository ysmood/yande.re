$ = (sel, el = document) ->
	document.querySelectorAll.call el, sel

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
		$('.page span')[0].textContent = data.page_num
		$('.err span')[0].textContent = data.err_count

	xhr.send()

auto_update = ->
	set_state()
	setInterval set_state, 1000

auto_update()
