" =============================================================================
" {{ theme_name }}: the Kadomo theme's colors for Vim, as the "kadomo"
" colorscheme. ~/.vim/colors/kadomo.vim links here; Vim picks up a new theme
" the next time it starts.
"
" The highlight design is tmac2k's: keywords take color 1, defines 2, types 3,
" functions 4, strings 5, constants 6, so every theme reads the same way.
" =============================================================================

set background={{ mode }}
highlight clear
if exists("syntax_on")
  syntax reset
endif
let g:colors_name = "kadomo"

" =============================================================================
" PALETTE  (by the role tmac2k gives each color)
" =============================================================================
" color 1  keywords, operators      color 4  functions, methods
" color 2  statements, defines      color 5  strings, imports
" color 3  types, class names       color 6  constants, numbers
" =============================================================================

" Helper: hi Group guifg guibg gui    cterm
" -----------------------------------------------------------------------------

" --- UI Chrome ---------------------------------------------------------------
hi Normal           guifg={{ foreground }}   guibg={{ background }}   gui=NONE        cterm=NONE
hi NormalNC         guifg={{ foreground }}   guibg={{ dim_background }}   gui=NONE        cterm=NONE
hi LineNr           guifg={{ muted }}   guibg=NONE      gui=NONE        cterm=NONE
hi CursorLine       guifg=NONE      guibg={{ shade }}   gui=NONE        cterm=NONE
hi CursorLineNr     guifg={{ color3 }}   guibg=NONE      gui=bold        cterm=bold
hi CursorColumn     guifg=NONE      guibg={{ shade }}   gui=NONE        cterm=NONE
hi ColorColumn      guifg=NONE      guibg={{ shade }}   gui=NONE        cterm=NONE
hi SignColumn       guifg={{ selection }}   guibg={{ background }}   gui=NONE        cterm=NONE
hi VertSplit        guifg={{ selection }}   guibg={{ background }}   gui=NONE        cterm=NONE
hi StatusLine       guifg={{ foreground }}   guibg={{ selection }}   gui=NONE        cterm=NONE
hi StatusLineNC     guifg={{ selection }}   guibg={{ shade }}   gui=NONE        cterm=NONE
hi TabLine          guifg={{ foreground }}   guibg={{ selection }}   gui=NONE        cterm=NONE
hi TabLineFill      guifg=NONE      guibg={{ shade }}   gui=NONE        cterm=NONE
hi TabLineSel       guifg={{ bright_foreground }}   guibg={{ color3 }}   gui=bold        cterm=bold
hi Folded           guifg={{ color4 }}   guibg={{ shade }}   gui=italic      cterm=NONE
hi FoldColumn       guifg={{ color4 }}   guibg={{ background }}   gui=NONE        cterm=NONE

" --- Selection / Search ------------------------------------------------------
hi Visual           guifg={{ foreground }}   guibg={{ selection }}   gui=NONE        cterm=NONE
hi VisualNOS        guifg={{ foreground }}   guibg={{ selection }}   gui=NONE        cterm=NONE
hi Search           guifg={{ background }}   guibg={{ color1 }}   gui=NONE        cterm=NONE
hi IncSearch        guifg={{ background }}   guibg={{ color6 }}   gui=bold        cterm=bold
hi MatchParen       guifg={{ color6 }}   guibg=NONE      gui=bold,underline cterm=bold

" --- Cursor ------------------------------------------------------------------
hi Cursor           guifg={{ background }}   guibg={{ foreground }}   gui=NONE        cterm=NONE
hi iCursor          guifg={{ background }}   guibg={{ color6 }}   gui=NONE        cterm=NONE
hi vCursor          guifg={{ background }}   guibg={{ color1 }}   gui=NONE        cterm=NONE

" --- Popup / Menu ------------------------------------------------------------
hi Pmenu            guifg={{ foreground }}   guibg={{ selection }}   gui=NONE        cterm=NONE
hi PmenuSel         guifg={{ bright_foreground }}   guibg={{ color3 }}   gui=bold        cterm=bold
hi PmenuSbar        guifg=NONE      guibg={{ shade }}   gui=NONE        cterm=NONE
hi PmenuThumb       guifg=NONE      guibg={{ color4 }}   gui=NONE        cterm=NONE
hi WildMenu         guifg={{ bright_foreground }}   guibg={{ color4 }}   gui=bold        cterm=bold

" --- Messages / Prompts ------------------------------------------------------
hi ModeMsg          guifg={{ color6 }}   guibg=NONE      gui=bold        cterm=bold
hi MoreMsg          guifg={{ color6 }}   guibg=NONE      gui=bold        cterm=bold
hi Question         guifg={{ color5 }}   guibg=NONE      gui=bold        cterm=bold
hi WarningMsg       guifg={{ color1 }}   guibg=NONE      gui=bold        cterm=bold
hi ErrorMsg         guifg={{ bright_foreground }}   guibg={{ color1 }}   gui=bold        cterm=bold

" --- Diff --------------------------------------------------------------------
hi DiffAdd          guifg={{ color2 }}   guibg={{ diff_background }}   gui=NONE        cterm=NONE
hi DiffChange       guifg={{ color5 }}   guibg={{ diff_background }}   gui=NONE        cterm=NONE
hi DiffDelete       guifg={{ color1 }}   guibg={{ dim_background }}   gui=NONE        cterm=NONE
hi DiffText         guifg={{ color6 }}   guibg={{ diff_background }}   gui=bold        cterm=bold

" --- Spelling ----------------------------------------------------------------
hi SpellBad         guifg={{ color1 }}   guibg=NONE      gui=undercurl   cterm=underline
hi SpellCap         guifg={{ color4 }}   guibg=NONE      gui=undercurl   cterm=underline
hi SpellRare        guifg={{ color3 }}   guibg=NONE      gui=undercurl   cterm=underline
hi SpellLocal       guifg={{ color5 }}   guibg=NONE      gui=undercurl   cterm=underline

" --- Misc UI -----------------------------------------------------------------
hi NonText          guifg={{ selection }}   guibg=NONE      gui=NONE        cterm=NONE
hi SpecialKey       guifg={{ selection }}   guibg=NONE      gui=NONE        cterm=NONE
hi EndOfBuffer      guifg={{ selection }}   guibg=NONE      gui=NONE        cterm=NONE
hi Directory        guifg={{ color4 }}   guibg=NONE      gui=bold        cterm=bold
hi Title            guifg={{ color1 }}   guibg=NONE      gui=bold        cterm=bold
hi Conceal          guifg={{ color3 }}   guibg=NONE      gui=NONE        cterm=NONE

" =============================================================================
" SYNTAX HIGHLIGHTING
" =============================================================================

" --- Core syntax groups ------------------------------------------------------
"  Comment        -> dark gray / muted (de-emphasized, italic)
"  Constant        -> cyan  numbers, booleans, nil
"  String          -> sky blue
"  Character       -> sky blue
"  Number          -> cyan
"  Boolean         -> cyan
"  Float           -> cyan
"  Identifier      -> light gray (normal text)
"  Function        -> periwinkle
"  Statement       -> violet   if/else/return/for…
"  Conditional     -> violet
"  Repeat          -> violet
"  Label           -> violet
"  Operator        -> violet
"  Keyword         -> violet
"  Exception       -> violet
"  PreProc         -> sky blue  import/from/#include
"  Include         -> sky blue
"  Define          -> purple
"  Macro           -> purple
"  PreCondit       -> sky blue
"  Type            -> blue-purple
"  StorageClass    -> blue-purple
"  Structure       -> blue-purple
"  Typedef         -> blue-purple
"  Special         -> cyan
"  SpecialChar     -> cyan
"  Tag             -> periwinkle
"  Delimiter       -> light gray
"  SpecialComment  -> purple italic
"  Debug           -> violet
"  Underlined      -> sky blue underlined
"  Error           -> white on violet
"  Todo            -> black on cyan bold

hi Comment          guifg={{ selection }}   guibg=NONE      gui=italic      cterm=italic
" Make comments slightly brighter so they're readable on pure black
hi Comment          guifg={{ comment }}   guibg=NONE      gui=italic      cterm=italic

hi Constant         guifg={{ color6 }}   guibg=NONE      gui=NONE        cterm=NONE
hi String           guifg={{ color5 }}   guibg=NONE      gui=NONE        cterm=NONE
hi Character        guifg={{ color5 }}   guibg=NONE      gui=NONE        cterm=NONE
hi Number           guifg={{ color6 }}   guibg=NONE      gui=NONE        cterm=NONE
hi Boolean          guifg={{ color6 }}   guibg=NONE      gui=bold        cterm=bold
hi Float            guifg={{ color6 }}   guibg=NONE      gui=NONE        cterm=NONE

hi Identifier       guifg={{ foreground }}   guibg=NONE      gui=NONE        cterm=NONE
hi Function         guifg={{ color4 }}   guibg=NONE      gui=NONE        cterm=NONE

hi Statement        guifg={{ color1 }}   guibg=NONE      gui=NONE        cterm=NONE
hi Conditional      guifg={{ color1 }}   guibg=NONE      gui=NONE        cterm=NONE
hi Repeat           guifg={{ color1 }}   guibg=NONE      gui=NONE        cterm=NONE
hi Label            guifg={{ color1 }}   guibg=NONE      gui=NONE        cterm=NONE
hi Operator         guifg={{ color1 }}   guibg=NONE      gui=NONE        cterm=NONE
hi Keyword          guifg={{ color1 }}   guibg=NONE      gui=NONE        cterm=NONE
hi Exception        guifg={{ color1 }}   guibg=NONE      gui=bold        cterm=bold

hi PreProc          guifg={{ color5 }}   guibg=NONE      gui=NONE        cterm=NONE
hi Include          guifg={{ color5 }}   guibg=NONE      gui=NONE        cterm=NONE
hi Define           guifg={{ color2 }}   guibg=NONE      gui=NONE        cterm=NONE
hi Macro            guifg={{ color2 }}   guibg=NONE      gui=NONE        cterm=NONE
hi PreCondit        guifg={{ color5 }}   guibg=NONE      gui=NONE        cterm=NONE

hi Type             guifg={{ color3 }}   guibg=NONE      gui=NONE        cterm=NONE
hi StorageClass     guifg={{ color3 }}   guibg=NONE      gui=NONE        cterm=NONE
hi Structure        guifg={{ color3 }}   guibg=NONE      gui=NONE        cterm=NONE
hi Typedef          guifg={{ color3 }}   guibg=NONE      gui=bold        cterm=bold

hi Special          guifg={{ color6 }}   guibg=NONE      gui=NONE        cterm=NONE
hi SpecialChar      guifg={{ color6 }}   guibg=NONE      gui=NONE        cterm=NONE
hi Tag              guifg={{ color4 }}   guibg=NONE      gui=NONE        cterm=NONE
hi Delimiter        guifg={{ foreground }}   guibg=NONE      gui=NONE        cterm=NONE
hi SpecialComment   guifg={{ color2 }}   guibg=NONE      gui=italic      cterm=italic
hi Debug            guifg={{ color1 }}   guibg=NONE      gui=NONE        cterm=NONE

hi Underlined       guifg={{ color5 }}   guibg=NONE      gui=underline   cterm=underline
hi Ignore           guifg={{ selection }}   guibg=NONE      gui=NONE        cterm=NONE
hi Error            guifg={{ bright_foreground }}   guibg={{ color1 }}   gui=bold        cterm=bold
hi Todo             guifg={{ background }}   guibg={{ color6 }}   gui=bold        cterm=bold

" =============================================================================
" LANGUAGE-SPECIFIC OVERRIDES
" =============================================================================

" --- Python ------------------------------------------------------------------
hi link pythonBuiltin        Constant
hi link pythonBuiltinObj     Type
hi link pythonBuiltinFunc    Function
hi link pythonFunction       Function
hi link pythonDecorator      PreProc
hi link pythonDecoratorName  PreProc
hi link pythonImport         Include
hi link pythonStatement      Keyword
hi link pythonConditional    Conditional
hi link pythonRepeat         Repeat
hi link pythonException      Exception
hi link pythonOperator       Operator
hi link pythonClass          Type
hi link pythonSelf           Special
hi link pythonDottedName     Identifier

" --- JavaScript / TypeScript -------------------------------------------------
hi link jsFunction           Keyword
hi link jsFuncName           Function
hi link jsArrowFunction      Operator
hi link jsImport             Include
hi link jsExport             Include
hi link jsModuleKeyword      Include
hi link jsClassKeyword       Keyword
hi link jsThis               Special
hi link jsSuper              Special
hi link jsNull               Constant
hi link jsUndefined          Constant
hi link jsBooleanTrue        Boolean
hi link jsBooleanFalse       Boolean
hi link jsTemplateBraces     Special
hi link typescriptImport     Include
hi link typescriptExport     Include
hi link typescriptType       Type
hi link typescriptInterface  Type
hi link typescriptKeyword    Keyword
hi link typescriptVariable   StorageClass

" --- HTML / CSS --------------------------------------------------------------
hi link htmlTag              Delimiter
hi link htmlEndTag           Delimiter
hi link htmlTagName          Type
hi link htmlArg              Identifier
hi link htmlSpecialChar      SpecialChar
hi link cssClassName         Function
hi link cssClassNameDot      Operator
hi link cssProp              Identifier
hi link cssValueLength       Number
hi link cssColor             Constant
hi link cssAtRule            PreProc

" --- Markdown ----------------------------------------------------------------
hi link markdownH1           Title
hi link markdownH2           Title
hi link markdownH3           Function
hi link markdownCode         String
hi link markdownCodeBlock    String
hi link markdownBold         Special
hi link markdownItalic       Comment
hi link markdownUrl          Underlined
hi link markdownLink         Function
hi link markdownLinkText     Identifier

" --- Git / Diff (fugitive) ---------------------------------------------------
hi link gitcommitSummary     Title
hi link gitcommitType        Keyword
hi link gitcommitFile        Identifier
hi link diffAdded            DiffAdd
hi link diffRemoved          DiffDelete
hi link diffChanged          DiffChange

" =============================================================================
" TRANSPARENT BACKGROUND
" =============================================================================
" The background is left to the terminal, so Ghostty's opacity and blur show
" through. Set g:kadomo_transparent = 0 (before loading it) for the theme's
" solid background instead.
if get(g:, 'kadomo_transparent', get(g:, 'tmac2k_transparent', 1))
  for s:group in ['Normal', 'NormalNC', 'SignColumn', 'VertSplit', 'FoldColumn']
    execute 'hi' s:group 'guibg=NONE ctermbg=NONE'
  endfor
endif

" =============================================================================
" TERMINAL COLORS  (Neovim / Vim 8+)
" =============================================================================
if has('termguicolors') || has('nvim')
  let g:terminal_color_0  = '{{ color0 }}'
  let g:terminal_color_1  = '{{ color1 }}'
  let g:terminal_color_2  = '{{ color2 }}'
  let g:terminal_color_3  = '{{ color3 }}'
  let g:terminal_color_4  = '{{ color4 }}'
  let g:terminal_color_5  = '{{ color5 }}'
  let g:terminal_color_6  = '{{ color6 }}'
  let g:terminal_color_7  = '{{ color7 }}'
  let g:terminal_color_8  = '{{ color8 }}'
  let g:terminal_color_9  = '{{ color9 }}'
  let g:terminal_color_10 = '{{ color10 }}'
  let g:terminal_color_11 = '{{ color11 }}'
  let g:terminal_color_12 = '{{ color12 }}'
  let g:terminal_color_13 = '{{ color13 }}'
  let g:terminal_color_14 = '{{ color14 }}'
  let g:terminal_color_15 = '{{ color15 }}'
endif

" vim: set ft=vim sw=2 ts=2:
