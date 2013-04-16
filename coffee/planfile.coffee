# Public Domain (-) 2012 The Planfile App Authors.
# See the Planfile App UNLICENSE file for details.

define 'planfile', (exports, root) ->

  if SAVED?
    delete root.localStorage['id']
    root.location = SAVED
    return

  doc = root.document
  doc.$ = doc.getElementById
  body = doc.body
  domly = util.domly
  loc = root.location
  ls = root.localStorage

  $selectDiv = $selectInput = $selectType = $selectWrap = null
  $selectResults = []

  selectCb = []
  selectCount = 5
  selectIdx = 0
  selectInfo = {}
  selectMode = null
  selectOn = false
  selectPrev = null
  selectTypes =
    edit: "Edit Item →"
    go: "Find/Filter →"

  countShowing = countTotal = 0
  normTag = {}
  original = []
  state = []
  tagNorm = {}
  tagTypes = {}

  $counter = $counterWrap = $dep = $editor = $form = $loader = $main = $preview = $root = null
  $formContent = $formID = $formPath = $formSummary = $formTags = $formTitle = $formXSRF = null
  $controls = {}
  $controlWraps = {}
  $planfiles = {}
  $summaries = {}

  [ANALYTICS_HOST, ANALYTICS_ID, repo, username, avatar, xsrf, isAuth] = root.DATA
  siteTitle = repo.title

  ajax = (url, data, callback) ->
    obj = new XMLHttpRequest()
    obj.onreadystatechange = ->
      callback obj if obj.readyState is 4
    obj.open "POST", url, true
    obj.send data
    obj

  escape = (evt) ->
    evt ||= root.event
    if evt.keyCode is 27
      if $formContent.value is original[0] and $formTags.value is original[1] and $formTitle.value is original[2]
        escapeEditor()

  escapeEditor = (evt) ->
    if evt
      evt.preventDefault()
    hideEditor()
    if '.editor' in state
      if state.length is 1
        state = []
      else
        state.splice state.indexOf('.editor'), 1
      setHistory()

  getDeps = (id, planfiles, collect) ->
    collect[id] = 1
    if not planfiles[id]
      return
    for id in planfiles[id].depends
      getDeps(id, planfiles, collect)

  getGotoItem = (id) ->
    (evt) ->
      if evt
        evt.preventDefault()
      updateState [".item.#{id}"]

  getEditor = (id, path, title, content, tags, action, isSummary, viaPop) ->
    (evt) ->
      hideSelect() if selectOn
      if not viaPop
        state.push '.editor'
        state.sort()
        history.pushState state, siteTitle, '/.editor'
      if (not isSummary) and tags is ''
        tags = 'TODO'
      $form.action = action
      $formContent.value = original[0] = content
      $formID.value = id
      $formPath.value = path
      $formTags.value = original[1] = tags
      $formTitle.value = original[2] = title
      if isSummary
        $formSummary.value = 'yes'
        hide $formTags
      else
        $formSummary.value = ''
        show $formTags
      $preview.innerHTML = ''
      doc.onkeydown = escape
      doc.onkeyup = null
      show $editor
      if viaPop
        if id
          $formTitle.focus()
      else
        $formTitle.focus()
      root.scroll 0, 0
      if evt
        evt.preventDefault()

  getFilterLabel = (id) ->
    (title) ->
      if id in state
        "#{title} <div class=enabled>ON</div>"
      else
        title

  getSelectCallback = (cb) ->
    (evt) ->
      if evt
        evt.preventDefault()
      hideSelect()
      cb()

  getShowID = (id) ->
    (evt) ->
      evt.preventDefault()
      root.prompt "Copy this:", id

  getShowTag = (tag) ->
    (evt) ->
      evt.preventDefault()
      if state.length is 1 and state[0] is tag
        return
      updateState [tag]

  getState = ->
    if path = loc.pathname.substr 1, loc.pathname.length
      if path.charAt(path.length - 1) is '/'
        path = path.substr 0, path.length - 1
      if path
        s = path.split '/'
        s.sort()
        return s
    return []

  getTags = (pf) ->
    res = (tag for tag in pf.tags)
    for tag in pf.depends
      res.push "dep:#{tag}"
    res.join ', '

  getToggler = (tag) ->
    (evt) ->
      if evt
        evt.preventDefault()
      if tag in state
        if state.length is 1
          state = []
        else
          state.splice state.indexOf(tag), 1
      else
        replace = false
        if state.length and tag isnt '.deps'
          for existing in state
            if existing.lastIndexOf('.item.', 0) is 0
              replace = true
        if replace
          state = [tag]
        else
          state.push tag
      updateState state

  gotoMainTag = ->
    totals = {}
    for _, planfile of $planfiles
      if planfile.style.display isnt 'none'
        for elem in planfile.querySelectorAll('a.tag')
          split = elem.href.split '/'
          tag = split[split.length-1].slice 0
          if totals[tag]
            totals[tag] += 1
          else
            totals[tag] = 1
    max = 0
    mainTag = null
    for tag, count of totals
      if count > max
        max = count
        mainTag = tag
    if mainTag
      if state.length is 1 and state[0] is mainTag
        return
      updateState [mainTag]

  handleKeys = (evt) ->
    evt ||= root.event
    key = evt.keyCode
    if key is 78
      getEditor('', '', '', '', '', '/.new')()
    else if key is 72
      if state.length
        updateState []
    else if key is 69
      showSelect 'edit'
    else if key is 70
      showSelect 'go'
    else if key is 76
      if username
        doc.location = '/.logout'
      else
        doc.location = '/.login'
    else if key is 77
      gotoMainTag()

  handleSelectMetaKeys = (evt) ->
    evt ||= root.event
    key = evt.keyCode
    if key is 27
      hideSelect()
    else if key is 13
      if cb = selectCb[selectIdx]
        cb()
      evt.preventDefault()
    else if key is 40
      if selectIdx < (l = selectCb.length) - 1
        selectIdx++
        i = 0
        while i < l
          if i == selectIdx
            $selectResults[i].className = 'item selected'
          else
            $selectResults[i].className = 'item'
          i++
      evt.preventDefault()
    else if key is 38
      if selectIdx
        selectIdx--
        i = 0
        l = selectCb.length
        while i < l
          if i == selectIdx
            $selectResults[i].className = 'item selected'
          else
            $selectResults[i].className = 'item'
          i++
      evt.preventDefault()

  handleSelectKeys = (evt, force) ->
    if force is true
      key = 41
    else
      evt ||= root.event
      key = evt.keyCode
    if not (key is 27 or key is 40 or key is 38)
      if (value = $selectInput.value) is selectPrev
        return
      selectPrev = value
      hide $selectWrap
      if value
        i = 0
        l = value.length
        pat = ''
        while i < l
          # TODO(tav): compare with:     /[-[\]{}()*+?.,\\^$|#\s]/g, '\\$&'
          pat += value.charAt(i).replace(/([.?*+^$[\]\\(){}|-])/g, '\\$1') + '+' # '+.*'
          i++
        regex = new RegExp(pat, 'i')
        info = selectInfo[selectMode]
        i = 0
        j = 0
        l = info.length
        selectCb = []
        while i < l
          data = info[i]
          if data.length is 2
            [item, cb] = data
            meta = null
          else
            [item, cb, meta] = data
          if regex.test item
            elem = $selectResults[j]
            if meta
              elem.innerHTML = meta(item)
            else
              elem.innerHTML = item
            elem.onclick = selectCb[j] = getSelectCallback cb
            show elem
            j++
            if j == 1
              selectIdx = 0
              elem.className = 'item selected'
            else
              elem.className = 'item'
            if j is selectCount
              break
          i++
        if j
          while j < selectCount
            hide $selectResults[j]
            j++
          show $selectWrap
      else
        selectResults = []

  hide = (element) ->
    element.style.display = 'none'

  hideEditor = (evt) ->
    hide $editor
    doc.onkeydown = null
    doc.onkeyup = handleKeys

  hideSelect = ->
    hide $selectDiv
    hide $selectWrap
    selectOn = false
    doc.onkeydown = null
    doc.onkeyup = handleKeys

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
    $selectDiv = domly ['div.select'], $main, true
    $selectType = domly ['div.type'], $selectDiv, true
    $selectInput = domly ['input', spellcheck: '', type: 'text'], $selectDiv, true
    $selectWrap = domly ['div.results'], $selectDiv, true
    $selectWrap.onmouseover = selectOver
    $selectWrap.onmouseout = selectOut
    for i in [0...selectCount]
      item = domly ['div.item', 'hi'], $selectWrap, true
      hide item
      $selectResults.push item
    hide $selectWrap
    hide $selectDiv
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
    append ['div.controls',
            ['a', onclick: showPreview, 'Render Preview'],
            ['a', onclick: escapeEditor, 'Cancel'],
            ['input', type: 'submit', onclick: submitForm, value: 'Save'],
          ]
    padtop = append ['div.padtop']
    $formSummary = domly ['input', type: 'hidden', name: 'summary', value: ''], padtop, true
    $loader = domly ['span.loader'], padtop, true
    domly ['div.clear'], $editor
    $preview = domly ['div.preview'], $editor, true
    hide $editor
    hide $preview

  renderEntries = ->
    selectInfo['edit'] = selects = []
    goSelects = selectInfo['go']
    $entries = domly ['div.entries'], $main, true
    tag_summaries = repo.tag_summaries
    for id, pf of tag_summaries
      if id is '/'
        selectID = 'README'
        entry = $root = domly ['div.entry'], $entries, true
        setInnerHTML entry, pf.rendered, 'content'
      else
        selectID = id
        entry = $summaries[id] = domly ['div.entry'], $entries, true
        if pf.title
          domly ['div.summary-title', pf.title], entry, true
        setInnerHTML entry, pf.rendered, 'content'
      editor = getEditor(id, pf.path, pf.title, pf.content, '', '/.modify', true)
      if isAuth
        domly ['div.tags', ['a.edit', href: '/.editor', onclick: editor, 'Edit']], entry
      selects.push ["Summary: #{selectID}", editor]
    if isAuth
      for _, wrap of $controlWraps
        if not tag_summaries[tag = wrap.tag]
          editor = getEditor("summary.#{tag}", "summary.#{tag}.md", '', '', '', '/.new', true)
          elem = ['a.summary', href: '/.editor', onclick: editor, "+ Add summary for #{normTag[tag]}"]
          $summaries[tag] = domly ['div.entry', ['div.content', elem]], $entries, true
    planfiles = repo.planfiles
    for id in repo.ordering
      pf = repo.planfiles[id]
      if not pf
        continue
      tags = ['div.tags']
      tags.push ['a.perma', href: "/.item.#{id}", '#']
      ptags = pf.tags.slice(0)
      ptags.reverse()
      for tag in ptags
        if tag.toUpperCase() isnt tag
          tags.push ["a.tag.tag-#{tagTypes[tag]}", href: "/#{tagNorm[tag]}", onclick: getShowTag(tagNorm[tag]), tag]
      editor = getEditor(id, pf.path, pf.title, pf.content, getTags(pf), '/.modify')
      if isAuth
        tags.push ['a.edit', href: '/.editor', onclick: editor, 'Edit']
      tags.push ['a.edit', href: "/.deps/.item.#{id}", 'Show Deps']
      tags.push ['a.edit', href: '/#', onclick: getShowID("dep:#{id}"), 'Get ID']
      entry = $planfiles[id] = domly [
        'div.entry', ['div.status-wrap', ["span.status.status-#{pf.status.toLowerCase()}", pf.status]], ['div.title', pf.title or pf.path]
        ], $entries, true
      setInnerHTML entry, pf.rendered, 'content'
      domly ['div', tags], entry
      selects.push [pf.title or pf.path, editor]
      goSelects.push [pf.title or pf.path, getGotoItem id]
      countTotal += 1
    countShowing = countTotal
    updateCounter()

  renderHeader = ->
    header = ['div.container']
    if username
      header.push ['a.button.logout', href: "/.logout", "Logout #{username}", ['img', src: avatar]]
      if isAuth
        # header.push ['a.button', href: '/.refresh', 'Refresh!']
        header.push ['a.button.edit', href: '/.create', onclick: getEditor('', '', '', '', '', '/.new'), '+ New Entry']
    else
      header.push ['a.button.login', href: '/.login', 'Login with GitHub']
    header.push ['div.logo', ['a', href: '/', siteTitle]]
    domly ['div.header', header], body

  renderSidebar = ->
    selectInfo['go'] = selects = []
    $elems = domly ['div.sidebar'], $main, true
    append = (elem, tag) ->
      div = domly ['div'], $elems, true
      if tag
        div.tag = tag
        $controlWraps[tag] = div
      domly elem, div, true
    $counter = append ['a', href: '/', '']
    $counterWrap = $counter.parentNode
    for tag in repo.tags
      norm = tag
      s = tag[0]
      if s is '#'
        tagTypes[tag] = 'hashtag'
        norm = tag.slice 1
      else if (s is '@') or (s is '+')
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
      toggler = getToggler(norm)
      $controls[norm] = append ["a.#{ext}", href: "/#{norm}", unselectable: 'on', onclick: toggler, tag], norm
      selects.push [tag, toggler, getFilterLabel(norm)]
    if '.deps' in state
      ext = '.selected'
    else
      ext = ''
    toggler = getToggler('.deps')
    $dep = append ["a.#{ext}", href: '/.deps', unselectable: 'on', onclick: toggler, 'SHOW DEPS']
    selects.push ['SHOW DEPS', toggler, getFilterLabel('.deps')]

  renderState = (s, setControls) ->
    if setControls
      for _, control of $controls
        control.className = ''
      $dep.className = ''
    for _, summary of $summaries
      hide summary
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
        if s[0] is '.editor'
          if ls['id']?
            getEditor(ls['id'], ls['path'], ls['title'], ls['content'], ls['tags'], ls['action'], ls['summary'] is 'yes', true)()
          else
            getEditor('', '', '', '', '', '/.new', false, true)()
          s = s.slice 1, l
        else
          hideEditor()
      else
        hideEditor()
      if l = s.length
        found = null
        if l is 1
          tag = s[0]
          if tag.lastIndexOf('.item.', 0) is 0
            if plan = $planfiles[id = tag.slice 6]
              found = [id]
              countShowing = 1
          else if $controls[tag]
            if $summaries[tag]
              show $summaries[tag]
            if setControls
              $controls[tag].className = 'selected'
            found = repo.tag_map[normTag[tag]]
        else
          tag_map = repo.tag_map
          for norm in s
            if setControls and (control = $controls[norm])
              control.className = 'selected'
            if items = tag_map[normTag[norm]]
              if found
                found = intersect items, found
              else
                found = items
            else
              break
        subtags = {}
        if found
          if deps
            collect = {}
            for id in found
              getDeps(id, repo.planfiles, collect)
            found = (id for id, _ of collect)
          countShowing = 0
          planfiles = repo.planfiles
          for id in found
            countShowing += 1
            show $planfiles[id]
            for t in planfiles[id].tags
              subtags[tagNorm[t]] = 1
        for _, control of $controlWraps
          if subtags[ctag = control.tag] or ctag in state
            show control
          else
            hide control
        updateCounter()
        return
    else
      hideEditor()
    if $root
      show $root
    for _, control of $controlWraps
      show control
    for _, planfile of $planfiles
      show planfile
    countShowing = countTotal
    updateCounter()

  selectOut = ->
    i = 0
    for elem in $selectResults
      if i is selectIdx
        elem.className = 'item selected'
      else
        elem.className = 'item'
      i++

  selectOver = ->
    for elem in $selectResults
      elem.className = 'item'

  setHistory = ->
    if state.length
      state.sort()
      url = '/' + state.join '/'
    else
      url = '/'
    history.pushState state, siteTitle, url

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
    show $preview
    $preview.innerHTML = 'loading preview ...'
    ajax '/.preview', form, (xhr) ->
      if xhr.status is 200
        $preview.innerHTML = xhr.responseText

  showSelect = (t) ->
    selectOn = true
    selectMode = t
    selectPrev = ''
    $selectType.innerHTML = selectTypes[t]
    $selectInput.value = ""
    for i in [0...selectCount]
      hide $selectResults[i]
    doc.onkeyup = handleSelectKeys
    doc.onkeydown = handleSelectMetaKeys
    show $selectDiv
    if state.length
      if t is 'edit' and (item = state[state.length-1]).lastIndexOf('.item.', 0) is 0 and plan = repo.planfiles[item.slice 6]
        $selectInput.value = plan.title
        handleSelectKeys null, true
        $selectInput.select()
      else if t is 'filter'
        found = false
        for elem in state
          if $controls[elem]
            $selectInput.value = normTag[elem]
            handleSelectKeys null, true
            $selectInput.select()
        if not found
          $selectInput.focus()
      else
        $selectInput.focus()
    else
      $selectInput.focus()
    return

  submitForm = ->
    if not $formID.value
      $formID.value = $formTitle.value.toLowerCase().replace(/[^a-zA-Z0-9]+/g, '-')
    $formTags.value = (tag.trim() for tag in $formTags.value.split(',')).join(', ')
    $formXSRF.value = xsrf
    ls['content'] = $formContent.value
    ls['id'] = $formID.value
    ls['path'] = $formPath.value
    ls['tags'] = $formTags.value
    ls['title'] = $formTitle.value
    ls['action'] = $form.action
    ls['summary'] = $formSummary.value
    i = 1
    t = 'SAVING '
    indicator = ->
      if not (i % 20)
        t = 'SAVING '
      else
        t += '.'
      i++
      $loader.innerHTML = t
    setInterval indicator, 100

  updateCounter = ->
    if countTotal is countShowing
      $counter.innerHTML = "Showing All (#{countShowing})"
    else
      $counter.innerHTML = "Showing #{countShowing}/#{countTotal}"

  updateState = (s) ->
    state = s
    setHistory()
    renderState state, true
    root.scroll 0, 0

  doc.onkeyup = handleKeys

  exports.run = ->
    initAnalytics()
    for prop in ['addEventListener', 'FormData', 'XMLHttpRequest']
      if !root[prop]
        alert "Sorry, this app only works on newer browsers with HTML5 features :("
        return
    if doc.createTouch?
      body.className = 'touch'
    hide body
    state = getState()
    renderHeader()
    $main = domly ['div.container'], (domly ['div.container-ext'], (domly ['div.main'], body, true), true), true
    renderEditor()
    renderSidebar()
    renderEntries()
    if state.length
      renderState state, true
    else
      for _, summary of $summaries
        hide summary
    show body

  root.onpopstate = (e) ->
    if e.state
      renderState(state = e.state, true)
    else
      s = getState()
      if s.join('/') isnt state.join('/')
        renderState(state = s, true)

if not SAVED?
  planfile.run()