# Public Domain (-) 2012 The Planfile App Authors.
# See the Planfile App UNLICENSE file for details.

define 'planfile', (exports, root) ->

  doc = root.document
  doc.$ = doc.getElementById
  body = doc.body
  domly = amp.domly
  rmtree = amp.rmtree

  [ANALYTICS_HOST, ANALYTICS_ID, repo, username, avatar, isAuth] = root.DATA

  initAnalytics = ->
    if ANALYTICS_ID and doc.location.hostname isnt 'localhost'
      root._gaq = [
        ['_setAccount', ANALYTICS_ID]
        ['_setDomainName', ANALYTICS_HOST]
        ['_trackPageview']
      ]
      (->
        ga = doc.createElement 'script'
        ga.type = 'text/javascript'
        ga.async = true
        if doc.location.protocol is 'https:'
          ga.src = 'https://ssl.google-analytics.com/ga.js'
        else
          ga.src = 'http://www.google-analytics.com/ga.js'
        s = doc.getElementsByTagName('script')[0]
        s.parentNode.insertBefore(ga, s)
        return
      )()
    return

  renderForm = (action) ->
    form = ['form', action: action, method: "post"]

  renderHeader = ->
    if username
      header = ['div', $: 'container header',
        ['a', href: "/.logout", $: 'button logout',
          "Logout #{username}"
          ['img', src: avatar],
        ],
      ]
    else
      header = ['div', $: 'container header',
        ['a', href: '/.login', $: 'button login', 'Login with GitHub']
      ]
    domly header, body

  getToggler = (tag) ->
    ->
      alert tag

  tagTypes = {}
  $planfiles = null

  renderBar = ->
    elems = ['div', $: 'container tag-menu']
    tags = repo.tags.slice(0)
    tags.reverse()
    for tag in tags
      norm = tag
      s = tag[0]
      if s is '#'
        tagTypes[tag] = 'hashtag'
        norm = tag.slice 1
      else if s is '@'
        tagTypes[tag] = 'user'
      else if s.toUpperCase() is s
        tagTypes[tag] = 'state'
      else
        tagTypes[tag] = 'custom'
      elems.push ['a', href: "/#{norm}", onclick: getToggler(tag), tag]
    domly elems, body
    if isAuth
      domly ['div', $: 'container', ['a', $: 'button', href: '/.refresh', 'Refresh']], body

  renderPlan = (typ, id, pf) ->
    if id == '/'
      title = "Planfile"
    else
      title = pf.title or pf.path
    tags = ['div', $: 'tags']
    pf.tags.reverse()
    for tag in pf.tags
      tags.push ['span', $: "tag-#{tagTypes[tag]}", tag]
    ['section', $: 'entry', ['h1', title], ['div', id: "#{typ}-#{id}"], tags]

  renderPlans = ->
    elems = ['div', id: 'planfiles', $: 'container planfiles', style: 'display: none;']
    for id, pf of repo.sections
      elems.push renderPlan('overview', id, pf)
    for id, pf of repo.planfiles
      elems.push renderPlan('planfile', id, pf)
    domly elems, body
    for id, pf of repo.sections
      doc.$("overview-#{id}").innerHTML = pf.rendered
    for id, pf of repo.planfiles
      doc.$("planfile-#{id}").innerHTML = pf.rendered
    $planfiles = doc.$ 'planfiles'

  exports.run = ->
    initAnalytics()
    for prop in ['XMLHttpRequest', 'addEventListener']
      if !root[prop]
        alert "Sorry, this app only works on newer browsers with HTML5 features :("
        return
    renderHeader()
    renderBar()
    renderPlans()
    $planfiles.style.display = 'block'

  ajax = (url, method, callback, params) ->
    obj = new XMLHttpRequest()
    obj.onreadystatechange = ->
      callback obj if obj.readyState is 4
    obj.open method, url, true
    obj.send params
    obj

planfile.run()
