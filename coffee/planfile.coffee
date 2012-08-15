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

  exports.run = ->
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