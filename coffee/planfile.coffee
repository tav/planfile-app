define 'planfile', (exports, root) ->

  doc = root.document
  doc.$ = root.getElementByID
  body = doc.body
  domly = exports.domly
  local = root.localStorage

  container = doc.createElement 'div'
  container.id = 'body'
  body.insertAdjacentElement 'afterbegin', container

  exports.getLogin = getLogin = ->
    body.getAttribute('data-user')

  exports.getAvatarURL = getAvatarURL = ->
    body.getAtrribute('data-avatar-url')

  exports.showIndexLogin = showIndexLogin = ->
    data = [
      'div', id: 'home',
          ['div', class: 'container header',
            ['a', href: '/login', class: 'button login', 'Log in with GitHub']
          ]
    ]
    domly data, container

  exports.showIndexLoggedIn = showIndexLoggedIn = ->
    userName = getLogin()
    data = [
      'div', id: 'home',
        ['div', class: 'container header',
            ['div', class: 'logo',
              ['a', id: 'logo', "planfile"],
            ],
            ['div', class: 'user_controls',
              ['a', id: 'user',
                ['img', src: ''],
                ['span', userName],
              ]
              ['div', class: '',
                ['a', href: "/logout", id: 'logout', "Log out"]
              ]
            ]
        ],
        ['div', class: 'container planfiles',
          ['p', class: 'title', 'Your plan files'],
          ['ul']
        ]
    ]
    domly data, container

    ajax('https://api.github.com/users/' + userName, 'GET', (resp) ->
      avatarImage = body.querySelector('.user_controls img')
      user = JSON.parse(resp.responseText)
      avatarImage.src = user.avatar_url
    )

    addPlanfileItem = (item) ->
      li = document.createElement('li')
      li.appendChild(( ->
        a = document.createElement('a')
        a.textContent = item.name
        a.href = '/' + item.full_name
        a
      )())
      li.appendChild(( ->
        small = document.createElement('small')
        small.textContent = item.description
        small
        )())
      li

    ajax('https://api.github.com/users/' + userName + '/repos', 'GET', (resp) ->
      avatarImage = body.querySelector('.user_controls img')
      repos = JSON.parse(resp.responseText)
      planfiles = (addPlanfileItem(item) for item in repos when /planfile/.test(item.name))
      list = body.querySelector('.planfiles ul')
      list.appendChild(item) for item in planfiles
    )

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