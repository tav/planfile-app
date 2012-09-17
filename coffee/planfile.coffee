# Public Domain (-) 2012 The Planfile App Authors.
# See the Planfile App UNLICENSE file for details.

define 'planfile', (exports, root) ->

  doc = root.document
  doc.$ = doc.getElementById
  body = doc.body
  domly = amp.domly
  loc = root.location

  normTag = {}
  state = []
  tagNorm = {}
  tagTypes = {}

  $dep = $editor = $form = $main = $preview = $root = null
  $formContent = $formID = $formPath = $formSection = $formTags = $formTitle = $formXSRF = null
  $controls = {}
  $planfiles = {}
  $sections = {}

  [ANALYTICS_HOST, ANALYTICS_ID, siteTitle, clippy, repo, username, avatar, xsrf, isAuth] = root.DATA

  ajax = (url, data, callback) ->
    obj = new XMLHttpRequest()
    obj.onreadystatechange = ->
      callback obj if obj.readyState is 4
    obj.open "POST", url, true
    obj.send data
    obj

  getDeps = (id, planfiles, collect) ->
    collect[id] = 1
    if not planfiles[id]
      return
    for id in planfiles[id].depends
      getDeps(id, planfiles, collect)

  getTags = (pf) ->
    res = (tag for tag in pf.tags)
    for tag in pf.depends
      res.push "dep:#{tag}"
    res.join ', '

  hide = (element) ->
    element.style.display = 'none'

  initAnalytics = ->
    if ANALYTICS_ID and loc.hostname isnt 'localhost'
      root._gaq = [
        ['_setAccount', ANALYTICS_ID]
        ['_setDomainName', ANALYTICS_HOST]
        ['_trackPageview']
      ]
      (->
        ga = doc.createElement 'script'
        if loc.protocol is 'https:'
          ga.src = 'https://ssl.google-analytics.com/ga.js'
        else
          ga.src = 'http://www.google-analytics.com/ga.js'
        s = doc.getElementsByTagName('script')[0]
        s.parentNode.insertBefore(ga, s)
        return
      )()
    return

  intersect = (a, b) ->
    i = j = 0
    al = a.length
    bl = b.length
    r = []
    while i < al and j < bl
      if a[i] < b[j]
        i++
      else if b[j] < a[i]
        j++
      else
        r.push a[i]
        i++
        j++
    return r

  renderEditor = ->
    $editor = domly ['div.editor'], $main, true
    $form = domly ['form', method: 'post', action: '/.new'], $editor, true
    append = (elems) ->
      domly elems, $form, true
    $formXSRF = append ['input', type: 'hidden', name: 'xsrf']
    $formID = append ['input', type: 'hidden', name: 'id']
    $formPath = append ['input', type: 'hidden', name: 'path']
    $formTitle = append ['input', type: 'text', name: 'title', placeholder: 'Title']
    $formContent = append ['textarea', name: 'content', placeholder: 'Content', '']
    $formTags = append ['input', type: 'text', name: 'tags', placeholder: 'Tags']
    $formSection = append ['input', type: 'checkbox', id: 'f0', name: 'section', onclick: swapTagMode(), checked: '']
    append ['div.controls',
            ['a', onclick: showPreview, 'Render Preview'],
            ['a', onclick: (-> hide($editor)), 'Cancel'],
            ['input', type: 'submit', onclick: submitForm, value: 'Save'],
          ]
    append ['label', for: 'f0', ' Section']
    $preview = domly ['div.preview'], $editor, true
    hide $editor

  renderEntries = ->
    $entries = domly ['div.entries'], $main, true
    for id, pf of repo.sections
      if id is '/'
        entry = $root = domly ['div.entry'], $entries, true
        $root.innerHTML = pf.rendered
      else
        entry = $sections[tagNorm[id]] = domly ['div.entry', ['h2', pf.title or pf.path]], $entries, true
        setInnerHTML entry, pf.rendered
      if isAuth
        domly ['div.tags', ['a.edit', onclick: getUpdatedEditor(id, pf.path, pf.title, pf.content, '', '/.modify', true), 'Edit']], entry
    for id, pf of repo.planfiles
      if pf.done
        mark = '✓ '
      else
        mark = '✗ '
      tags = ['div.tags']
      pf.tags.reverse()
      for tag in pf.tags
        tags.push ["span.tag.tag-#{tagTypes[tag]}", tag]
      if isAuth
        tags.push ['a.edit', onclick: getUpdatedEditor(id, pf.path, pf.title, pf.content, getTags(pf), '/.modify'), 'Edit']
      if pf.depends.length
        tags.push ['a.edit', href: "/.deps/.item.#{id}", 'Show Deps']
      entry = $planfiles[id] = domly ['div.entry', ['h3', mark, ['span.title', pf.title or pf.path]]], $entries, true
      setInnerHTML entry, pf.rendered, 'content'
      domly ['div', tags], entry

  renderHeader = ->
    header = ['div.container']
    if username
      header.push ['a.button.logout', href: "/.logout", "Logout #{username}", ['img', src: avatar]]
      if isAuth
        header.push ['a.button', href: '/.refresh', 'Refresh!']
        header.push ['a.button.edit', href: '/.create', onclick: getUpdatedEditor('', '', '', '', [], '/.new'), '+ New Entry']
    else
      header.push ['a.button.login', href: '/.login', 'Login with GitHub']
    header.push ['div.logo', ['a', href: '/', siteTitle]]
    domly ['div.header', header], body

  renderSidebar = ->
    $elems = domly ['div.sidebar'], $main, true
    if '.deps' in state
      ext = '.selected'
    else
      ext = ''
    append = (elem) ->
      div = domly ['div'], $elems, true
      domly elem, div, true
    $dep = append ["a.#{ext}", href: '/.deps', unselectable: 'on', onclick: getToggler('.deps'), 'SHOW DEPS']
    for tag in repo.tags
      norm = tag
      s = tag[0]
      if s is '#'
        tagTypes[tag] = 'hashtag'
        norm = tag.slice 1
      else if s is '@'
        tagTypes[tag] = 'user'
      else if tag.toUpperCase() is tag
        tagTypes[tag] = "state-#{tag.toLowerCase()}"
      else
        tagTypes[tag] = 'custom'
        norm = ".tag.#{tag}"
      normTag[norm] = tag
      tagNorm[tag] = norm
      if norm in state
        ext = '.selected'
      else
        ext = ''
      $controls[norm] = append ["a.#{ext}", href: "/#{norm}", unselectable: 'on', onclick: getToggler(norm), tag]

  renderState = (s, setControls) ->
    if setControls
      for _, control of $controls
        control.className = ''
      $dep.className = ''
    for _, section of $sections
      hide section
    for _, planfile of $planfiles
      hide planfile
    if l = s.length
      if $root
        hide $root
      if deps = (s[0] is '.deps')
        s = s.slice 1, l
        if setControls
          $dep.className = 'selected'
      if l = s.length
        found = null
        if l is 1
          tag = s[0]
          if tag.lastIndexOf('.item.', 0) is 0
            if plan = $planfiles[id = tag.slice 6]
              found = [id]
          else if $controls[tag]
            if $sections[tag]
              show $sections[tag]
            if setControls
              $controls[tag].className = 'selected'
            found = repo.tagmap[normTag[tag]]
        else
          tagmap = repo.tagmap
          for norm in s
            if setControls and (control = $controls[norm])
              control.className = 'selected'
            if items = tagmap[normTag[norm]]
              if found
                found = intersect items, found
              else
                found = items
            else
              break
        if found
          if deps
            collect = {}
            for id in found
              getDeps(id, repo.planfiles, collect)
            found = (id for id, _ of collect)
          for id in found
            show $planfiles[id]
        return
    if $root
      show $root
    for _, planfile of $planfiles
      show planfile

  setInnerHTML = (elem, html, klass) ->
    div = doc.createElement 'div'
    div.innerHTML = html
    if klass
      div.className = klass
    elem.appendChild div

  show = (element) ->
    element.style.display = 'block'

  showPreview = ->
    form = new FormData()
    form.append 'content', $formContent.value
    ajax '/.preview', form, (xhr) ->
      if xhr.status is 200
        $preview.innerHTML = xhr.responseText

  submitForm = ->
    if not $formID.value
      $formID.value = $formTitle.value.toLowerCase().replace(/[^a-zA-Z0-9]+/g, '-')
    $formTags.value = (tag.trim() for tag in $formTags.value.split(',')).join(', ')
    $formXSRF.value = xsrf

  swapTagMode = ->
    ->
      if $formSection.checked
        $formTags.placeholder = 'Overview for Tag:'
      else
        $formTags.placeholder = 'Tags'

  getToggler = (tag) ->
    (evt) ->
      evt.preventDefault()
      if tag in state
        state.splice state.indexOf(tag), 1
      else
        state.push tag
      if state.length
        state.sort()
        url = '/' + state.join '/'
      else
        url = '/'
      history.pushState state, siteTitle, url
      renderState state, true

  getUpdatedEditor = (id, path, title, content, tags, action, isSection) ->
    (evt) ->
      $form.action = action
      $formContent.value = content
      $formID.value = id
      $formPath.value = path
      $formTags.value = tags
      $formTitle.value = title
      if isSection
        $formSection.checked = true
        $formTags.placeholder = 'Overview for Tag:'
        if id is '/'
          $formTitle.value = 'README'
          $formTags.value = 'README'
      else
        $formSection.checked = false
        $formTags.placeholder = 'Tags'
      $preview.innerHTML = ''
      show $editor
      $formTitle.focus()
      root.scroll 0, 0
      evt.preventDefault()

  exports.run = ->
    initAnalytics()
    for prop in ['addEventListener', 'FormData', 'XMLHttpRequest']
      if !root[prop]
        alert "Sorry, this app only works on newer browsers with HTML5 features :("
        return
    hide body
    if path = loc.pathname.substr 1, loc.pathname.length
      if path.charAt(path.length - 1) is '/'
        path = path.substr 0, path.length - 1
      if path
        state = path.split '/'
        state.sort()
    renderHeader()
    $main = domly ['div.container'], (domly ['div.main'], body, true), true
    renderEditor()
    renderSidebar()
    renderEntries()
    if state.length
      renderState state, true
    else
      for _, section of $sections
        hide section
    show body

  root.onpopstate = (e) ->
    renderState(state = e.state, true) if e.state

planfile.run()