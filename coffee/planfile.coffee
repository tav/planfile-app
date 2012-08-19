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

  tagString = (tags) ->
    rTags = []
    for tag in tags
      if tag[0] is '#'
        rTags.push tag.substr(1)
      else
        rTags.push tag
    rTags

  renderState = (tags, deps) ->
    entries = doc.querySelectorAll('section.entry div[id|=planfile]')
    root =  doc.querySelector('div[id*=overview-]')
    if tags.length isnt 0
      hide root.parentNode
    else
      show root.parentNode
    tagLinks = doc.querySelectorAll('.tag-menu a')
    for link in tagLinks
      link.className = ''
    for tag in tags
      for link in tagLinks
        if link.textContent is tag
          link.className = 'clicked'
    for entry in entries
      name = entry.id.substr(9)
      if matchState(tags, repo.planfiles[name].tags)
        show entry.parentNode
      else
        hide entry.parentNode

  window.onpopstate = (e) ->
    if !e.state
      [tags, deps] = buildState()
      renderState(tags, deps)
    else
      renderState(e.state.tags, e.state.deps)

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
      history.pushState({tags: tags, deps: deps}, '', '/' + join(tagString(tags), '/'))
      renderState(tags, deps)

  exports.run = ->
    initAnalytics()
    for prop in ['addEventListener', 'FormData', 'XMLHttpRequest']
      if !root[prop]
        alert "Sorry, this app only works on newer browsers with HTML5 features :("
        return
    renderHeader()
    renderBar()
    renderPlans()
    [tags, deps] = buildState()
    renderState(tags, deps)
    $content = domly ['textarea', ''], body, true
    domly ['a', onclick: showPreview, 'Render Preview'], body
    $preview = domly ['div', id: 'preview'], body, true
    $planfiles.style.display = 'block'

planfile.run()
