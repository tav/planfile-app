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

  hide = (element) ->
    element.setAttribute 'style', 'display: none;'

  show = (element) ->
    element.setAttribute 'style', ''

  deleteElement = (array, element) ->
    if element in array
      array.splice(array.indexOf(element), 1)

  pushUnique = (array, element) ->
    if element not in array
      array.push element

  endsWith = (st, suf) ->
    st.length >= suf.length and st.substr(st.length - suf.length) is suf

  isHashTag = (tag) ->
    n = '#' + tag
    tagTypes[n] and tagTypes[n] is 'hashtag'

  buildState = ->
     tags = location.pathname.substr(1).split('/')
     deleteElement tags, ''
     for tag in tags
       if isHashTag tag
         deleteElement tags, tag
         pushUnique tags, '#' + tag
     deps = endsWith(location.pathname, ':deps')
     [tags, deps]

  [tags, deps] = [[], false]

  matchState = (stags, tags) ->
    count = 0
    for t in stags
      if t in tags
        count += 1
    stags.length is count

  renderState = (tags, deps) ->
    entries = doc.querySelectorAll('section.entry div[id|=planfile]')
    root =  doc.querySelector('div[id*=overview-]')
    if tags.length isnt 0
      hide root.parentNode
    else
      show root.parentNode
    for entry in entries
      name = entry.id.substr(9)
      if matchState(tags, repo.planfiles[name].tags)
        show entry.parentNode
      else
        hide entry.parentNode

  getToggler = (tag) ->
    ->
      e = window.event
      e.stopPropagation()
      e.preventDefault()
      deps = false
      if !@.className
        pushUnique(tags, tag)
        @.className = 'clicked'
      else
        deleteElement(tags, tag)
        @.className = ''
      renderState(tags, deps)

  exports.run = ->
    initAnalytics()
    for prop in ['XMLHttpRequest', 'addEventListener']
      if !root[prop]
        alert "Sorry, this app only works on newer browsers with HTML5 features :("
        return
    renderHeader()
    renderBar()
    renderPlans()
    [tags, deps] = buildState()
    renderState(tags, deps)
    $planfiles.style.display = 'block'

  ajax = (url, method, callback, params) ->
    obj = new XMLHttpRequest()
    obj.onreadystatechange = ->
      callback obj if obj.readyState is 4
    obj.open method, url, true
    obj.send params
    obj

planfile.run()
