fun! Filename(...)
    let filename = expand('%:t:r')
    if filename == '' | return a:0 == 2 ? a:2 : '' | endif
    return !a:0 || a:1 == '' ? filename : substitute(a:1, '$1', filename, 'g')
endf

fun! GObjectNS()
    let fnlist = split(expand('%:t:r'), '[-_]')
    if len(fnlist) >1
        return toupper(join(fnlist[:-2], '_'))
    endif
    return 'NAMESPACE'
endf

fun! GObjectMO()
    let fnlist = split(expand('%:t:r'), '[-_]')
    if len(fnlist) >1
        return toupper(fnlist[-1])
    endif
    return 'MODULE'
endf

fun! GObjectNs()
    let fnlist = split(tolower(expand('%:t:r')), '[-_]')
    if fnlist[0] == 'ibus'
        let fnlist[0] = 'IBus'
    endif
    if len(fnlist) >1
        return join(map(fnlist[:-2], 'toupper(v:val[0]).v:val[1:]'), '')
    endif
    return 'Namespace'
endf

fun! GObjectMo()
    let fnlist = split(expand('%:t:r'), '[-_]')
    if len(fnlist) >1
        return toupper(fnlist[-1][0]).fnlist[-1][1:]
    endif
    return 'Module'
endf

fun! GObjectNsm()
    let fnlist = split(expand('%:t:r'), '[-_]')
    if len(fnlist) >1
        return tolower(join(fnlist, '_'))
    endif
    return 'namespace_module'
endf

fun s:RemoveSnippet()
    unl! g:snipPos g:snipCurPos s:snipLen g:endCol g:endLine s:prevLen
         \ s:lastBuf s:oldWord
    if exists('g:snipUpdate')
        unl s:startCol s:origWordLen g:snipUpdate
        if exists('s:oldVars') | unl s:oldVars s:oldEndCol | endif
    endif
    if exists('snipMateAutocmds')
        aug! snipMateAutocmds
    endif
endf

fun snipMate#expandSnip(snip, col)
    " if we expand in the last tabstop, we start a new round
    if exists('g:snipPos') && g:snipCurPos == s:snipLen - 1
        call s:RemoveSnippet()
    endif
    let lnum = line('.') | let col = a:col
    let snippet = s:ProcessSnippet(a:snip)
    " Avoid error if eval evaluates to nothing
    if snippet == '' | return '' | endif

    " Expand snippet onto current position with the tab stops removed
    let snipLines = split(substitute(snippet, '$\d\+\|${\d\+.\{-}}', '', 'g'), "\n", 1)
    " We need to record the snippet lines and cols if we in multi level
    " expanding

    let addedLines = len(snipLines) - 1
    let addedCols = len(snipLines[-1])
    let line = getline(lnum)
    let afterCursor = strpart(line, col - 1)
    " Keep text after the cursor
    if afterCursor != "\t" && afterCursor != ' '
        let line = strpart(line, 0, col - 1)
        let snipLines[-1] .= afterCursor
    else
        let afterCursor = ''
        " For some reason the cursor needs to move one right after this
        if line != '' && col == 1 && &ve != 'all' && &ve != 'onemore'
            let col += 1
        endif
    endif

    call setline(lnum, line.snipLines[0])

    " Autoindent snippet according to previous indentation
    let indent = matchend(line, '^.\{-}\ze\(\S\|$\)') + 1
    call append(lnum, map(snipLines[1:], "'".strpart(line, 0, indent - 1)."'.v:val"))

    " Open any folds snippet expands into
    if &fen | sil! exe lnum.','.(lnum + len(snipLines) - 1).'foldopen' | endif

    let [l:snipPos, l:snipLen] = s:BuildTabStops(snippet, lnum, col - indent, indent)

    if !exists('g:snipPos')
        let g:snipPos = []
    elseif exists('g:snipCurPos') && len(g:snipPos) > g:snipCurPos
        " In multi-level expansion, we need to update following tabstops
        let g:endLine += addedLines
        if len(snipLines) > 1
            let addedCols += indent - 1
        endif
        let g:endCol += addedCols
        call s:UpdateTabStops()
        call remove(g:snipPos, g:snipCurPos)
    endif

    if !exists('s:snipLen')
        let s:snipLen = 0
    elseif s:snipLen > 0
        let s:snipLen -= 1
    endif

    if exists('g:snipCurPos')
        call extend(g:snipPos, l:snipPos, g:snipCurPos)
    else
        call extend(g:snipPos, l:snipPos, 0)
    endif

    let s:snipLen += l:snipLen

    if l:snipLen
        aug snipMateAutocmds
            au CursorMovedI * call s:UpdateChangedSnip(0)
            au InsertEnter * call s:UpdateChangedSnip(1)
        aug END
        let s:lastBuf = bufnr(0) " Only expand snippet while in current buffer
        if !exists('g:snipCurPos')
            let g:snipCurPos = 0
        endif
        let g:endCol = g:snipPos[g:snipCurPos][1]
        let g:endLine = g:snipPos[g:snipCurPos][0]

        call cursor(g:snipPos[g:snipCurPos][0], g:snipPos[g:snipCurPos][1])
        let s:prevLen = [line('$'), col('$')]
        if g:snipPos[g:snipCurPos][2] != -1 | return s:SelectWord() | endif
    else
        call s:RemoveSnippet()
        " Place cursor at end of snippet if no tab stop is given
        let newlines = len(snipLines) - 1
        call cursor(lnum + newlines, len(snipLines[-1]) - len(afterCursor)
                    \ + (newlines ? indent : col))
    endif
    return ''
endf

" Prepare snippet to be processed by s:BuildTabStops
fun s:ProcessSnippet(snip)
    let snippet = a:snip
    " Evaluate eval (`...`) expressions.
    " Backquotes prefixed with a backslash "\" are ignored.
    " Using a loop here instead of a regex fixes a bug with nested "\=".
    if stridx(snippet, '`') != -1
        while match(snippet, '\(^\|[^\\]\)`.\{-}[^\\]`') != -1
            let snippet = substitute(snippet, '\(^\|[^\\]\)\zs`.\{-}[^\\]`\ze',
                        \ substitute(eval(matchstr(snippet, '\(^\|[^\\]\)`\zs.\{-}[^\\]\ze`')),
                        \ "\n\\%$", '', ''), '')
        endw
        let snippet = substitute(snippet, "\r", "\n", 'g')
        let snippet = substitute(snippet, '\\`', '`', 'g')
    endif

    " Place all text after a colon in a tab stop after the tab stop
    " (e.g. "${#:foo}" becomes "${:foo}foo").
    " This helps tell the position of the tab stops later.
    let snippet = substitute(snippet, '${\d\+:\(.\{-}\)}', '&\1', 'g')

    " Update the a:snip so that all the $# become the text after
    " the colon in their associated ${#}.
    " (e.g. "${1:foo}" turns all "$1"'s into "foo")
    let i = 1
    while stridx(snippet, '${'.i) != -1
        let s = matchstr(snippet, '${'.i.':\zs.\{-}\ze}')
        if s != ''
            let snippet = substitute(snippet, '$'.i, s.'&', 'g')
        endif
        let i += 1
    endw

    if &et " Expand tabs to spaces if 'expandtab' is set.
        return substitute(snippet, '\t', repeat(' ', &sts ? &sts : &sw), 'g')
    endif
    return snippet
endf

" Counts occurences of haystack in needle
fun s:Count(haystack, needle)
    let counter = 0
    let index = stridx(a:haystack, a:needle)
    while index != -1
        let index = stridx(a:haystack, a:needle, index+1)
        let counter += 1
    endw
    return counter
endf

" Builds a list of a list of each tab stop in the snippet containing:
" 1.) The tab stop's line number.
" 2.) The tab stop's column number
"     (by getting the length of the string between the last "\n" and the
"     tab stop).
" 3.) The length of the text after the colon for the current tab stop
"     (e.g. "${1:foo}" would return 3). If there is no text, -1 is returned.
" 4.) If the "${#:}" construct is given, another list containing all
"     the matches of "$#", to be replaced with the placeholder. This list is
"     composed the same way as the parent; the first item is the line number,
"     and the second is the column.
fun s:BuildTabStops(snip, lnum, col, indent)
    let snipPos = []
    let i = 1
    let withoutVars = substitute(a:snip, '$\d\+', '', 'g')
    while stridx(a:snip, '${'.i) != -1
        let beforeTabStop = matchstr(withoutVars, '^.*\ze${'.i.'\D')
        let withoutOthers = substitute(withoutVars, '${\('.i.'\D\)\@!\d\+.\{-}}', '', 'g')
        " if we process {$1:aa}
        " now the beforeTabStop is the str before ${1
        " withoutOthers is the whole string without ${2:aa} and ${3} etc.

        " vim start index from 0, but we let user start index from 1. Thus we
        " need to recover the true index in vim list
        let j = i - 1
        " ['word before $','the name in ${1:name}']
        call add(snipPos, [0, 0, -1, ''])

        let snipPos[j][0] = a:lnum + s:Count(beforeTabStop, "\n")
        let snipPos[j][1] = a:indent + len(matchstr(withoutOthers, '.*\(\n\|^\)\zs.*\ze${'.i.'\D'))
        let snipPos[j][3] = matchstr(beforeTabStop, '\S\+$')
        if snipPos[j][0] == a:lnum | let snipPos[j][1] += a:col | endif

        " Get all $# matches in another list, if ${#:name} is given
        if stridx(withoutVars, '${'.i.':') != -1
            let snipPos[j][2] = len(matchstr(withoutVars, '${'.i.':\zs.\{-}\ze}'))
            let dots = repeat('.', snipPos[j][2])
            call add(snipPos[j], [])
            " here only the placeholder $i left
            let withoutOthers = substitute(a:snip, '${\d\+.\{-}}\|$'.i.'\@!\d\+', '', 'g')
            while match(withoutOthers, '$'.i.'\(\D\|$\)') != -1
                let beforeMark = matchstr(withoutOthers, '^.\{-}\ze'.dots.'$'.i.'\(\D\|$\)')
                call add(snipPos[j][4], [0, 0])
                let snipPos[j][4][-1][0] = a:lnum + s:Count(beforeMark, "\n")
                let snipPos[j][4][-1][1] = a:indent + (snipPos[j][4][-1][0] > a:lnum
                                           \ ? len(matchstr(beforeMark, '.*\n\zs.*'))
                                           \ : a:col + len(beforeMark))
                let withoutOthers = substitute(withoutOthers, '$'.i.'\ze\(\D\|$\)', '', '')
            endw
        endif
        let i += 1
    endw
    return [snipPos, i - 1]
endf

fun snipMate#jumpTabStop(backwards)
    let leftPlaceholder = exists('s:origWordLen')
                          \ && s:origWordLen != g:snipPos[g:snipCurPos][2]
    if leftPlaceholder && exists('s:oldEndCol')
        let startPlaceholder = s:oldEndCol + 1
    endif

    if exists('g:snipUpdate')
        call s:UpdatePlaceholderTabStops()
    else
        call s:UpdateTabStops()
    endif

    " Don't reselect placeholder if it has been modified
    if leftPlaceholder && g:snipPos[g:snipCurPos][2] != -1
        if exists('startPlaceholder')
            let g:snipPos[g:snipCurPos][1] = startPlaceholder
        else
            let g:snipPos[g:snipCurPos][1] = col('.')
            let g:snipPos[g:snipCurPos][2] = 0
        endif
    endif

    let g:snipCurPos += a:backwards ? -1 : 1
    " Loop over the snippet when going backwards from the beginning
    if g:snipCurPos < 0 | let g:snipCurPos = s:snipLen - 1 | endif

    if g:snipCurPos == s:snipLen
        let sMode = g:endCol == g:snipPos[g:snipCurPos-1][1]+g:snipPos[g:snipCurPos-1][2]
        call s:RemoveSnippet()
        return sMode ? "\<tab>" : TriggerSnippet()
    endif

    call cursor(g:snipPos[g:snipCurPos][0], g:snipPos[g:snipCurPos][1])

    let g:endLine = g:snipPos[g:snipCurPos][0]
    let g:endCol = g:snipPos[g:snipCurPos][1]
    let s:prevLen = [line('$'), col('$')]

    return g:snipPos[g:snipCurPos][2] == -1 ? '' : s:SelectWord()
endf

fun s:UpdatePlaceholderTabStops()
    let changeLen = s:origWordLen - g:snipPos[g:snipCurPos][2]
    unl s:startCol s:origWordLen g:snipUpdate
    if !exists('s:oldVars') | return | endif
    " Update tab stops in snippet if text has been added via "$#"
    " (e.g., in "${1:foo}bar$1${2}").
    if changeLen != 0
        let curLine = line('.')

        for pos in g:snipPos
            if pos == g:snipPos[g:snipCurPos] | continue | endif
            let changed = pos[0] == curLine && pos[1] > s:oldEndCol
            let changedVars = 0
            let endPlaceholder = pos[2] - 1 + pos[1]
            " Subtract changeLen from each tab stop that was after any of
            " the current tab stop's placeholders.
            for [lnum, col] in s:oldVars
                if lnum > pos[0] | break | endif
                if pos[0] == lnum
                    if pos[1] > col || (pos[2] == -1 && pos[1] == col)
                        let changed += 1
                    elseif col < endPlaceholder
                        let changedVars += 1
                    endif
                endif
            endfor
            let pos[1] -= changeLen * changed
            let pos[2] -= changeLen * changedVars " Parse variables within placeholders
                                                  " e.g., "${1:foo} ${2:$1bar}"

            if pos[2] == -1 | continue | endif
            " Do the same to any placeholders in the other tab stops.
            for nPos in pos[4]
                let changed = nPos[0] == curLine && nPos[1] > s:oldEndCol
                for [lnum, col] in s:oldVars
                    if lnum > nPos[0] | break | endif
                    if nPos[0] == lnum && nPos[1] > col
                        let changed += 1
                    endif
                endfor
                let nPos[1] -= changeLen * changed
            endfor
        endfor
    endif
    unl g:endCol s:oldVars s:oldEndCol
endf

fun s:UpdateTabStops()
    let changeLine = g:endLine - g:snipPos[g:snipCurPos][0]
    let changeCol = g:endCol - g:snipPos[g:snipCurPos][1]
    if exists('s:origWordLen')
        let changeCol -= s:origWordLen
        unl s:origWordLen
    endif
    let lnum = g:snipPos[g:snipCurPos][0]
    let col = g:snipPos[g:snipCurPos][1]
    " Update the line number of all proceeding tab stops if <cr> has
    " been inserted.
    if changeLine != 0
        for pos in g:snipPos
            if pos[0] >= lnum
                if pos[0] == lnum | let pos[1] += changeCol | endif
                let pos[0] += changeLine
            endif
            if pos[2] == -1 | continue | endif
            for nPos in pos[4]
                if nPos[0] >= lnum
                    if nPos[0] == lnum | let nPos[1] += changeCol | endif
                    let nPos[0] += changeLine
                endif
            endfor
        endfor
    elseif changeCol != 0
        " Update the column of all proceeding tab stops if text has
        " been inserted/deleted in the current line.
        for pos in g:snipPos
            if pos[1] >= col && pos[0] == lnum
                let pos[1] += changeCol
            endif
            if pos[2] == -1 | continue | endif
            for nPos in pos[4]
                if nPos[0] > lnum | break | endif
                if nPos[0] == lnum && nPos[1] >= col
                    let nPos[1] += changeCol
                endif
            endfor
        endfor
    endif
endf

fun s:SelectWord()
    let s:origWordLen = g:snipPos[g:snipCurPos][2]
    let s:oldWord = strpart(getline('.'), g:snipPos[g:snipCurPos][1] - 1,
                \ s:origWordLen)
    let s:prevLen[1] -= s:origWordLen
    if !empty(g:snipPos[g:snipCurPos][4])
        let g:snipUpdate = 1
        let g:endCol = -1
        let s:startCol = g:snipPos[g:snipCurPos][1] - 1
    endif
    if !s:origWordLen | return '' | endif
    let l = col('.') != 1 ? 'l' : ''
    if &sel == 'exclusive'
        return "\<esc>".l.'v'.s:origWordLen."l\<c-g>"
    endif
    return s:origWordLen == 1 ? "\<esc>".l.'gh'
                            \ : "\<esc>".l.'v'.(s:origWordLen - 1)."l\<c-g>"
endf

" This updates the snippet as you type when text needs to be inserted
" into multiple places (e.g. in "${1:default text}foo$1bar$1",
" "default text" would be highlighted, and if the user types something,
" UpdateChangedSnip() would be called so that the text after "foo" & "bar"
" are updated accordingly)
"
" It also automatically quits the snippet if the cursor is moved out of it
" while in insert mode.
fun s:UpdateChangedSnip(entering)
    if exists('g:snipPos') && bufnr(0) != s:lastBuf
        call s:RemoveSnippet()
    elseif exists('g:snipUpdate') " If modifying a placeholder
        if !exists('s:oldVars') && g:snipCurPos + 1 < s:snipLen
            " Save the old snippet & word length before it's updated
            " s:startCol must be saved too, in case text is added
            " before the snippet (e.g. in "foo$1${2}bar${1:foo}").
            let s:oldEndCol = s:startCol
            let s:oldVars = deepcopy(g:snipPos[g:snipCurPos][4])
        endif
        let col = col('.') - 1

        if g:endCol != -1
            let changeLen = col('$') - s:prevLen[1]
            let g:endCol += changeLen
        else " When being updated the first time, after leaving select mode
            if a:entering | return | endif
            let g:endCol = col - 1
        endif

        " If the cursor moves outside the snippet, quit it
        if line('.') != g:snipPos[g:snipCurPos][0] || col < s:startCol ||
                    \ col - 1 > g:endCol
            unl! s:startCol s:origWordLen s:oldVars g:snipUpdate
            return s:RemoveSnippet()
        endif

        call s:UpdateVars()
        let s:prevLen[1] = col('$')
    elseif exists('g:snipPos')
        if !a:entering && g:snipPos[g:snipCurPos][2] != -1
            let g:snipPos[g:snipCurPos][2] = -2
        endif

        let col = col('.')
        let lnum = line('.')
        let changeLine = line('$') - s:prevLen[0]

        if lnum == g:endLine
            let g:endCol += col('$') - s:prevLen[1]
            let s:prevLen = [line('$'), col('$')]
        endif
        if changeLine != 0
            let g:endLine += changeLine
            let g:endCol = col
            let s:prevLen = [line('$'), col('$')]
        endif

        " Delete snippet if cursor moves out of it in insert mode
        "if (lnum == g:endLine && (col > g:endCol || col < g:snipPos[g:snipCurPos][1]))
        "    \ || lnum > g:endLine || lnum < g:snipPos[g:snipCurPos][0]
        "    call s:RemoveSnippet()
        "endif
    endif
endf

" This updates the variables in a snippet when a placeholder has been edited.
" (e.g., each "$1" in "${1:foo} $1bar $1bar")
fun s:UpdateVars()
    let newWordLen = g:endCol - s:startCol + 1
    let newWord = strpart(getline('.'), s:startCol, newWordLen)
    if newWord == s:oldWord || empty(g:snipPos[g:snipCurPos][4])
        return
    endif

    let changeLen = g:snipPos[g:snipCurPos][2] - newWordLen
    let curLine = line('.')
    let startCol = col('.')
    let oldStartSnip = s:startCol
    let updateTabStops = changeLen != 0
    let i = 0

    for [lnum, col] in g:snipPos[g:snipCurPos][4]
        if updateTabStops
            let start = s:startCol
            if lnum == curLine && col <= start
                let s:startCol -= changeLen
                let g:endCol -= changeLen
            endif
            for nPos in g:snipPos[g:snipCurPos][4][(i):]
                " This list is in ascending order, so quit if we've gone too far.
                if nPos[0] > lnum | break | endif
                if nPos[0] == lnum && nPos[1] > col
                    let nPos[1] -= changeLen
                endif
            endfor
            if lnum == curLine && col > start
                let col -= changeLen
                let g:snipPos[g:snipCurPos][4][i][1] = col
            endif
            let i += 1
        endif

        " "Very nomagic" is used here to allow special characters.
        call setline(lnum, substitute(getline(lnum), '\%'.col.'c\V'.
                        \ escape(s:oldWord, '\'), escape(newWord, '\&'), ''))
    endfor
    if oldStartSnip != s:startCol
        call cursor(0, startCol + s:startCol - oldStartSnip)
    endif

    let s:oldWord = newWord
    let g:snipPos[g:snipCurPos][2] = newWordLen
endf
" vim:et:sw=4:ts=4:ft=vim
