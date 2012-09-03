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
  [planfiles, sections, tags, deps] = [[], [], [], false]

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
    form = ['form', action: action, method: 'post']

  renderHeader = ->
    if username
      header = ['div', $: 'container header',
        ['a', href: '/.logout', $: 'button logout',
          ['img', src: avatar]
          "Logout",
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
    ajax '/.preview', form, (xhr) ->
      if xhr.status is 200
        $preview.innerHTML = xhr.responseText

  submitForm = ->
    $form = doc.querySelector 'form'
    if $form.action is '/.new'
      $title = doc.querySelector 'form input[name=title]'
      $id = doc.querySelector 'form input[name=id]'
      $id.value = $title.value.replace(/[^a-zA-Z0-9]+/g, '-')
    # Simple tag post-processing
    $tags = doc.querySelector 'form input[name=tags]'
    tags = $tags.value
    $tags.value = (tag.trim() for tag in tags.split(',')).join(', ')
    $xsrf = doc.querySelector 'form input[name=xsrf]'
    $xsrf.value = xsrf
    $form.submit()

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

  showEditor = () ->
    $editor = doc.querySelector('.editor')
    $title = doc.querySelector('.editor input[name=title]')
    show $editor
    $title.focus()
    window.scroll(0, doc.height)

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
      domly ['div', $: 'container editor-controls',
          ['a', $: 'button', href: '/.refresh', 'Refresh'],
          ['a', $: 'button edit', onclick: getUpdatedEditor(null, '/.new'), '+']
      ], body

  getUpdatedEditor = (id, action) ->
    ->
      $form = doc.querySelector('form')
      $form.action = action
      $title = doc.querySelector('input[name=title]')
      $content = doc.querySelector('textarea')
      $tags = doc.querySelector('input[name=tags]')
      $id = doc.querySelector 'form input[name=id]'
      $section = doc.querySelector 'form input[name=section]'
      if id
        source = repo.planfiles[id] or repo.sections[id]
        $id.value = id
        $title.value = source.title
        $content.value = source.content
        $tags.value = source.tags.join(', ')
        $editor = doc.querySelector('.editor')
      else
        $id.value = ''
        $title.value = ''
        $content.value = ''
        $tags.value = ''
        $tags.placeholder = 'Tags'
        $section.checked = false
      showEditor()

  renderPlan = (typ, id, pf) ->
    if id == '/'
      title = 'Planfile'
      return ['section', $: 'entry', ['h1', title], ['div', id: "root"]]
    else
      title = pf.title or pf.path
    tags = ['div', $: 'tags']
    pf.tags.reverse()
    for tag in pf.tags
      tags.push ['span', $: "tag-#{tagTypes[tag]}", tag]
    if isAuth
      tags.push ['a', $: 'edit', onclick: getUpdatedEditor(id, '/.modify'), 'Edit']
    ['section', $: 'entry', ['h1', title], ['div', id: "#{typ}-#{id}"], tags]

  renderPlans = ->
    elems = ['div', id: 'planfiles', $: 'container planfiles', style: 'display: none;']
    for id, pf of repo.sections
      elems.push renderPlan('overview', id, pf)
    for id, pf of repo.planfiles
      elems.push renderPlan('planfile', id, pf)
    $planfiles = domly elems, body, true
    for id, pf of repo.sections
      if id is '/'
        doc.$('root').innerHTML = pf.rendered
      else
        doc.$("overview-#{id}").innerHTML = pf.rendered
    for id, pf of repo.planfiles
      doc.$("planfile-#{id}").innerHTML = pf.rendered

  buildState = (tags) ->
    split = location.pathname.replace(':deps', '').split('/')
    pfl = []
    sects = []
    if split[1] is '.item'
      pfl = [split[2]]
      tags = ['.item']
    else
      if !tags
        tags = location.pathname.replace(':deps', '').substr(1).split('/')
      deleteElement tags, ''
      for tag in tags
        if isHashTag tag
          deleteElement tags, tag
          pushUnique tags, '#' + tag
      for k, v of repo.planfiles
        if matchState(tags, v.tags)
          pfl.push k
      for k, v of repo.sections
        if tags[0] is k
          sects.push k
    # Build dependencies
    deps = endsWith(location.pathname, ':deps')
    if deps
      altPfl = []
      for pf in pfl
        for dep in repo.planfiles[pf].depends
          pushUnique altPfl, dep
      pfl = altPfl
    [pfl, sects, tags]

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

  toggle = (tags) ->
    if tags is ['.item']
      return
    tagLinks = doc.querySelectorAll('.tag-menu a')
    for link in tagLinks
      link.className = ''
    for tag in tags
      for link in tagLinks
        if link.textContent is tag
          link.className = 'clicked'

  renderState = (planfiles, sections, tags) ->
    # Render active tags
    pfs = doc.querySelectorAll('section.entry div[id|=planfile]')
    sects = doc.querySelectorAll('section.entry div[id|=overview]')
    docroot =  doc.$ 'root'
    toggle(tags)
    # Check if any planfiles or sections are specified
    if tags.length isnt 0
      hide docroot.parentNode
      for entry in pfs
        name = entry.id.substr(9)
        if name in planfiles
          show entry.parentNode
        else
          hide entry.parentNode
      for entry in sects
        name = entry.id.substr(9)
        if name in sections
          show entry.parentNode
        else
          hide entry.parentNode
    else
      show docroot.parentNode
      for entry in sects
        hide entry.parentNode
      if !deps
        for entry in pfs
          show entry.parentNode
      else
        for entry in pfs
          hide entry.parentNode
        for entry in sects
          hide entry.parentNode

  window.onpopstate = (e) ->
    if !e.state
      [planfiles, sections, tags] = buildState()
      renderState(planfiles, sections, tags)
    else
      renderState(e.state.planfiles, e.state.sections, e.state.tags)

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
      [planfiles, sections, tags] = buildState(tags)
      history.pushState({planfiles: planfiles, sections: sections, tags: tags}, '', '/' + join(tagString(tags), '/'))
      renderState(planfiles, sections, tags)

  closeEditor = ->
    hide doc.querySelector '.editor'

  swapTagMode = ->
    ->
      $tags = doc.querySelector 'input[name=tags]'
      $section = doc.querySelector 'input[name=section]'
      if $section.checked
        $tags.placeholder = 'Overview for tag:'
      else
        $tags.placeholder = 'Tags'

  initEdit = ->
    if isAuth
      elems =  ['div', $: 'container editor',
        ['form', method: "post", action: '/.new',
          ['input', type: 'hidden', name: 'xsrf'],
          ['input', type: 'hidden', name: 'id'],
          ['input', type: 'text', name: 'title', placeholder: 'Title'],
          ['textarea', name: 'content', placeholder: 'Content', ''],
          ['input', type: 'text', name: 'tags', placeholder: 'Tags'],
          ['label'
            ['input', type: 'checkbox', name: 'section', onclick: swapTagMode(), checked: ''],
            'Section']
          ['div', $: 'controls',
            ['a', onclick: showPreview, 'Render Preview'],
            ['a', onclick: closeEditor, 'Cancel'],
            ['input', type: 'submit', onclick: submitForm, value: 'Save'],
          ]
        ]
      ]
      domly elems, body
      $editor = doc.querySelector '.editor'
      $editor.setAttribute 'style', 'display: none;'
      $content = doc.querySelector '.editor textarea'
      $preview = domly ['div', id: 'preview'], $editor, true

  exports.run = ->
    initAnalytics()
    for prop in ['addEventListener', 'FormData', 'XMLHttpRequest']
      if !root[prop]
        alert "Sorry, this app only works on newer browsers with HTML5 features :("
        return
    renderHeader()
    renderBar()
    renderPlans()
    [planfiles, sections, tags] = buildState()
    renderState(planfiles, sections, tags)
    initEdit()
    $planfiles.style.display = 'block'

planfile.run()
