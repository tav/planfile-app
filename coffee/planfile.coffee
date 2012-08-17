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
    active = ''
    clicked = {}
    for tag in tagList.trim().split(" ")
      do (tag) ->
        tagElem = document.createElement 'a'
        tagElem.href = '#'
        tagText = tag.replace('tag-user-', '@').replace('tag-label-', '#')
        tagElem.textContent = tagText
        tagElem.setAttribute 'class', tag
        clicked[tag] = false
        tagElem.onclick = (e) ->
          tClass = ''
          if !clicked[tag]
            tClass = 'clicked '
            active = active.trim() + " " + tag
          else
            active = active.replace tag, ''
          search = (source, token) ->
            if source.search token > -1
              console.log 'found string'
              return 0
            return -1
          activeTags = active.trim().split(" ")
          searchAll = (target, items) ->
            count = 0
            for item in items
              do (item) ->
                if target.search(item) > -1
                  count += 1
            count
          targets = doc.querySelectorAll 'section'
          for target in targets
            do (target) ->
              oldClass = target.getAttribute 'class'
              if searchAll(oldClass, activeTags) == activeTags.length
                target.setAttribute 'style', ''
              else
                target.setAttribute 'style', 'display: none;'
          @.setAttribute('class', tClass + @.getAttribute('class').replace('clicked', ''))
          clicked[tag] = !clicked[tag]
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