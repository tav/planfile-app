# Public Domain (-) 2012 The Planfile App Authors.
# See the Planfile App UNLICENSE file for details.

define 'planfile', (exports, root) ->

  doc = root.document
  doc.$ = doc.getElementById
  body = doc.body
  domly = amp.domly
  rmtree = amp.rmtree

  tagTypes = {}
  $content = $planfiles = $preview = null

  [ANALYTICS_HOST, ANALYTICS_ID, repo, username, avatar, xsrf, isAuth] = root.DATA

  ajax = (url, data, callback) ->
    obj = new XMLHttpRequest()
    obj.onreadystatechange = ->
      callback obj if obj.readyState is 4
    obj.open "POST", url, true
    obj.send data
    obj

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

  showPreview = ->
    form = new FormData()
    form.append 'content', $content.value
    ajax "/.preview", form, (xhr) ->
      if xhr.status is 200
        $preview.innerHTML = xhr.responseText

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
    $planfiles = domly elems, body, true
    for id, pf of repo.sections
      doc.$("overview-#{id}").innerHTML = pf.rendered
    for id, pf of repo.planfiles
      doc.$("planfile-#{id}").innerHTML = pf.rendered

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

  join = (strings, sep) ->
    joined = ''
    for string, id in strings
      if id <= (strings.length - 2)
        joined += string + sep
      else
        joined += string
    joined

  buildState = (tags) ->
    split = location.pathname.split('/')
    if split[1] is '.item'
      pfl = [split[2]]
      tags = []
    else
      if !tags
        tags = location.pathname.substr(1).split('/')
      deleteElement tags, ''
      for tag in tags
        if isHashTag tag
          deleteElement tags, tag
          pushUnique tags, '#' + tag
      deps = endsWith(location.pathname, ':deps')
      pfl = []
      for k, v of repo.planfiles
        if matchState(tags, v.tags)
          pfl.push k
    # Build dependencies
    if deps
      altPfl = []
      for pf in pfl
        for dep in pf.depends
          pushUnique altPfl, dep
      pfl = altPfl
    [pfl, tags]

  [planfiles, tags] = [[], false]

  matchState = (stags, tags) ->
    count = 0
    for t in stags
      if t in tags
        count += 1
    stags.length is count and count > 0

  tagString = (tags) ->
    rTags = []
    for tag in tags
      if tag[0] is '#'
        rTags.push tag.substr(1)
      else
        rTags.push tag
    rTags

  renderState = (planfiles, tags) ->
    entries = doc.querySelectorAll('section.entry div[id|=planfile]')
    root =  doc.querySelector('div[id*=overview-]')
    tagLinks = doc.querySelectorAll('.tag-menu a')
    # Render active tags
    for link in tagLinks
      link.className = ''
    for tag in tags
      for link in tagLinks
        if link.textContent is tag
          link.className = 'clicked'
    # Check if any planfiles are specified
    if planfiles.length isnt 0
      hide root.parentNode
      for entry in entries
        name = entry.id.substr(9)
        if name in planfiles
          show entry
        else
          hide entry
    else
      show root.parentNode
      for entry in entries
        show entry

  window.onpopstate = (e) ->
    if !e.state
      [planfiles, tags] = buildState()
      renderState(planfiles, tags)
    else
      renderState(e.state.planfiles, e.state.tags)

  getToggler = (tag) ->
    ->
      e = window.event
      e.stopPropagation()
      e.preventDefault()
      deps = false
      if !@.className
        pushUnique(tags, tag)
      else
        deleteElement(tags, tag)
      [planfiles, tags] = buildState(tags)
      history.pushState({planfiles: planfiles, tags: tags}, '', '/' + join(tagString(tags), '/'))
      renderState(planfiles, tags)

  exports.run = ->
    initAnalytics()
    for prop in ['addEventListener', 'FormData', 'XMLHttpRequest']
      if !root[prop]
        alert "Sorry, this app only works on newer browsers with HTML5 features :("
        return
    renderHeader()
    renderBar()
    renderPlans()
    [planfiles, tags] = buildState()
    renderState(planfiles, tags)
    $content = domly ['textarea', ''], body, true
    domly ['a', onclick: showPreview, 'Render Preview'], body
    $preview = domly ['div', id: 'preview'], body, true
    $planfiles.style.display = 'block'

planfile.run()
