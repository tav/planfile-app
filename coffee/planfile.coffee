define 'planfile', (exports, root) ->

  doc = root.document
  doc.$ = root.getElementByID
  body = doc.body
  local = root.localStorage

  exports.getLogin = getLogin = ->
    body.getAttribute('data-user')

  exports.getAvatarURL = getAvatarURL = ->
    body.getAtrribute('data-avatar-url')

  exports.showIndexLogin = showIndexLogin = ->
    userName = getLogin()

  exports.showIndexLoggedIn = showIndexLoggedIn = ->
    userName = getLogin()

  exports.auth = auth = ->
    if getLogin() == '' then false else true

  buildTags = ->
    tagMenu = doc.createElement 'div'
    tagMenu.setAttribute 'class', 'container tag-menu'
    tagList = doc.querySelector('article input[type="hidden"]').value
    for tag in tagList.trim().split(" ")
      do (tag) ->
        tagElem = document.createElement('a')
        tagElem.href = '#'
        tagText = tag.replace('tag-user-', '@').replace('tag-label-', '#')
        tagElem.textContent = tagText
        tagElem.setAttribute 'class', tag
        clicked = false
        tagElem.onclick = (e) ->
          style = ''
          tClass = ''
          if !clicked
            style = 'display: none;'
            tClass = "clicked "
          targets = doc.querySelectorAll('section.' + tag)
          for target in targets
            do (target) ->
              oldStyle = target.getAttribute('style')
              target.setAttribute 'style', style
          @.setAttribute('class', tClass + @.getAttribute('class').replace('clicked', ''))
          clicked = !clicked
          e.preventDefault()
          return false
        tagMenu.appendChild tagElem
    header = doc.querySelector '.header'
    header.insertAdjacentElement 'afterend', tagMenu

  exports.run = ->
    buildTags()
    if auth()
      showIndexLoggedIn()
    else
      showIndexLogin()

  exports.ajax = ajax = (url, method, callback, params) ->
    obj = undefined
    try
      obj = new XMLHttpRequest()
    catch e
      try
        obj = new ActiveXObject("Msxml2.XMLHTTP")
      catch e
        try
          obj = new ActiveXObject("Microsoft.XMLHTTP")
        catch e
          alert "Your browser does not support Ajax."
          return false
    obj.onreadystatechange = ->
      callback obj  if obj.readyState is 4

    obj.open method, url, true
    obj.send params
    obj

((root, doc) ->

  root.planfile.run()

)(window, document)