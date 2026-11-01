-- =============================================================================
-- {{ theme_name }}: the Kadomo theme's colors for Neovim, as the "kadomo"
-- colorscheme. ~/.config/nvim/colors/kadomo.lua links here, and theme-set
-- reloads it in every running Neovim that shows it.
--
-- The highlight design is tmac2k's: keywords take color 1, defines 2, types 3,
-- functions 4, strings 5, constants 6, so every theme reads the same way.
-- The background is left to the terminal, so Ghostty's opacity and blur show
-- through. Set vim.g.kadomo_transparent = false (before loading it) for the
-- theme's solid background instead.
-- =============================================================================

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end
vim.o.background = "{{ mode }}"
vim.g.colors_name = "kadomo"

-- =============================================================================
-- PALETTE  (the theme's colors, by the role tmac2k gives them)
-- =============================================================================
local c = {
  bg = "{{ background }}",
  fg = "{{ foreground }}",
  gray = "{{ selection }}",          -- UI chrome, selection
  comment = "{{ comment }}",
  muted = "{{ muted }}",             -- line numbers
  shade = "{{ shade }}",             -- cursor line, panels
  dim = "{{ dim_background }}",      -- inactive windows
  diff = "{{ diff_background }}",    -- diff backgrounds
  violet = "{{ color1 }}",           -- keywords, operators
  purple = "{{ color2 }}",           -- defines, macros
  indigo = "{{ color3 }}",           -- types, class names
  blue = "{{ color4 }}",             -- functions, methods
  sky = "{{ color5 }}",              -- strings, imports
  cyan = "{{ color6 }}",             -- constants, numbers
  white = "{{ bright_foreground }}", -- bold / bright text
}

local transparent = vim.g.kadomo_transparent ~= false and vim.g.tmac2k_transparent ~= false
local bg = transparent and "NONE" or c.bg

local groups = {
  -- --- UI Chrome -------------------------------------------------------------
  Normal = { fg = c.fg, bg = bg },
  NormalNC = { fg = c.fg, bg = transparent and "NONE" or c.dim },
  LineNr = { fg = c.muted },
  CursorLine = { bg = c.shade },
  CursorLineNr = { fg = c.indigo, bold = true },
  CursorColumn = { bg = c.shade },
  ColorColumn = { bg = c.shade },
  SignColumn = { fg = c.gray, bg = bg },
  VertSplit = { fg = c.gray, bg = bg },
  WinSeparator = { fg = c.gray, bg = bg },
  StatusLine = { fg = c.fg, bg = c.gray },
  StatusLineNC = { fg = c.gray, bg = c.shade },
  WinBar = { fg = c.fg, bold = true },
  WinBarNC = { fg = c.comment },
  TabLine = { fg = c.fg, bg = c.gray },
  TabLineFill = { bg = c.shade },
  TabLineSel = { fg = c.white, bg = c.indigo, bold = true },
  Folded = { fg = c.blue, bg = c.shade, italic = true },
  FoldColumn = { fg = c.blue, bg = bg },

  -- --- Selection / Search ----------------------------------------------------
  Visual = { fg = c.fg, bg = c.gray },
  VisualNOS = { fg = c.fg, bg = c.gray },
  Search = { fg = c.bg, bg = c.violet },
  IncSearch = { fg = c.bg, bg = c.cyan, bold = true },
  CurSearch = { fg = c.bg, bg = c.cyan, bold = true },
  Substitute = { fg = c.bg, bg = c.purple },
  MatchParen = { fg = c.cyan, bold = true, underline = true },
  QuickFixLine = { bg = c.gray, bold = true },

  -- --- Cursor ----------------------------------------------------------------
  Cursor = { fg = c.bg, bg = c.fg },
  lCursor = { fg = c.bg, bg = c.fg },
  iCursor = { fg = c.bg, bg = c.cyan },
  vCursor = { fg = c.bg, bg = c.violet },
  TermCursor = { fg = c.bg, bg = c.fg },

  -- --- Popup / Menu / Floating windows ---------------------------------------
  Pmenu = { fg = c.fg, bg = c.gray },
  PmenuSel = { fg = c.white, bg = c.indigo, bold = true },
  PmenuSbar = { bg = c.shade },
  PmenuThumb = { bg = c.blue },
  PmenuKind = { fg = c.indigo, bg = c.gray },
  PmenuExtra = { fg = c.comment, bg = c.gray },
  WildMenu = { fg = c.white, bg = c.blue, bold = true },
  NormalFloat = { fg = c.fg, bg = c.shade },
  FloatBorder = { fg = c.blue, bg = c.shade },
  FloatTitle = { fg = c.violet, bg = c.shade, bold = true },
  FloatFooter = { fg = c.comment, bg = c.shade },

  -- --- Messages / Prompts ----------------------------------------------------
  ModeMsg = { fg = c.cyan, bold = true },
  MoreMsg = { fg = c.cyan, bold = true },
  Question = { fg = c.sky, bold = true },
  WarningMsg = { fg = c.violet, bold = true },
  ErrorMsg = { fg = c.white, bg = c.violet, bold = true },
  MsgArea = { fg = c.fg },

  -- --- Diff ------------------------------------------------------------------
  DiffAdd = { fg = c.purple, bg = c.diff },
  DiffChange = { fg = c.sky, bg = c.diff },
  DiffDelete = { fg = c.violet, bg = c.dim },
  DiffText = { fg = c.cyan, bg = c.diff, bold = true },
  Added = { fg = c.purple },
  Changed = { fg = c.sky },
  Removed = { fg = c.violet },

  -- --- Spelling --------------------------------------------------------------
  SpellBad = { sp = c.violet, undercurl = true },
  SpellCap = { sp = c.blue, undercurl = true },
  SpellRare = { sp = c.indigo, undercurl = true },
  SpellLocal = { sp = c.sky, undercurl = true },

  -- --- Misc UI ---------------------------------------------------------------
  NonText = { fg = c.gray },
  SpecialKey = { fg = c.gray },
  Whitespace = { fg = c.gray },
  EndOfBuffer = { fg = c.gray },
  Directory = { fg = c.blue, bold = true },
  Title = { fg = c.violet, bold = true },
  Conceal = { fg = c.indigo },

  -- ===========================================================================
  -- SYNTAX HIGHLIGHTING
  -- ===========================================================================
  Comment = { fg = c.comment, italic = true },
  Constant = { fg = c.cyan },
  String = { fg = c.sky },
  Character = { fg = c.sky },
  Number = { fg = c.cyan },
  Boolean = { fg = c.cyan, bold = true },
  Float = { fg = c.cyan },
  Identifier = { fg = c.fg },
  Function = { fg = c.blue },
  Statement = { fg = c.violet },
  Conditional = { fg = c.violet },
  Repeat = { fg = c.violet },
  Label = { fg = c.violet },
  Operator = { fg = c.violet },
  Keyword = { fg = c.violet },
  Exception = { fg = c.violet, bold = true },
  PreProc = { fg = c.sky },
  Include = { fg = c.sky },
  Define = { fg = c.purple },
  Macro = { fg = c.purple },
  PreCondit = { fg = c.sky },
  Type = { fg = c.indigo },
  StorageClass = { fg = c.indigo },
  Structure = { fg = c.indigo },
  Typedef = { fg = c.indigo, bold = true },
  Special = { fg = c.cyan },
  SpecialChar = { fg = c.cyan },
  Tag = { fg = c.blue },
  Delimiter = { fg = c.fg },
  SpecialComment = { fg = c.purple, italic = true },
  Debug = { fg = c.violet },
  Underlined = { fg = c.sky, underline = true },
  Ignore = { fg = c.gray },
  Error = { fg = c.white, bg = c.violet, bold = true },
  Todo = { fg = c.bg, bg = c.cyan, bold = true },

  -- ===========================================================================
  -- TREE-SITTER  (mapped as vim-colors.vim maps the per-language syntax groups)
  -- ===========================================================================
  ["@comment"] = { link = "Comment" },
  ["@comment.todo"] = { link = "Todo" },
  ["@comment.documentation"] = { link = "SpecialComment" },
  ["@string"] = { link = "String" },
  ["@string.escape"] = { link = "SpecialChar" },
  ["@string.regexp"] = { link = "Special" },
  ["@string.special"] = { link = "Special" },
  ["@string.special.url"] = { link = "Underlined" },
  ["@character"] = { link = "Character" },
  ["@number"] = { link = "Number" },
  ["@number.float"] = { link = "Float" },
  ["@boolean"] = { link = "Boolean" },
  ["@constant"] = { link = "Constant" },
  ["@constant.builtin"] = { link = "Constant" },
  ["@constant.macro"] = { link = "Macro" },
  ["@variable"] = { link = "Identifier" },
  ["@variable.builtin"] = { link = "Special" }, -- self, this, super
  ["@variable.parameter"] = { link = "Identifier" },
  ["@variable.member"] = { link = "Identifier" },
  ["@property"] = { link = "Identifier" },
  ["@module"] = { link = "Include" },
  ["@label"] = { link = "Label" },
  ["@function"] = { link = "Function" },
  ["@function.builtin"] = { link = "Function" },
  ["@function.call"] = { link = "Function" },
  ["@function.method"] = { link = "Function" },
  ["@function.method.call"] = { link = "Function" },
  ["@function.macro"] = { link = "Macro" },
  ["@constructor"] = { link = "Type" },
  ["@keyword"] = { link = "Keyword" },
  ["@keyword.function"] = { link = "Keyword" },
  ["@keyword.return"] = { link = "Keyword" },
  ["@keyword.operator"] = { link = "Operator" },
  ["@keyword.import"] = { link = "Include" },
  ["@keyword.conditional"] = { link = "Conditional" },
  ["@keyword.repeat"] = { link = "Repeat" },
  ["@keyword.exception"] = { link = "Exception" },
  ["@keyword.directive"] = { link = "PreProc" },
  ["@keyword.modifier"] = { link = "StorageClass" },
  ["@operator"] = { link = "Operator" },
  ["@punctuation.delimiter"] = { link = "Delimiter" },
  ["@punctuation.bracket"] = { link = "Delimiter" },
  ["@punctuation.special"] = { link = "Special" }, -- template braces
  ["@type"] = { link = "Type" },
  ["@type.builtin"] = { link = "Type" },
  ["@type.definition"] = { link = "Typedef" },
  ["@attribute"] = { link = "PreProc" }, -- decorators
  ["@tag"] = { link = "Type" },          -- HTML tag names
  ["@tag.attribute"] = { link = "Identifier" },
  ["@tag.delimiter"] = { link = "Delimiter" },
  ["@markup.heading"] = { link = "Title" },
  ["@markup.heading.3"] = { link = "Function" },
  ["@markup.strong"] = { fg = c.cyan, bold = true },
  ["@markup.italic"] = { fg = c.comment, italic = true },
  ["@markup.strikethrough"] = { strikethrough = true },
  ["@markup.underline"] = { link = "Underlined" },
  ["@markup.raw"] = { link = "String" },
  ["@markup.link"] = { link = "Function" },
  ["@markup.link.label"] = { link = "Identifier" },
  ["@markup.link.url"] = { link = "Underlined" },
  ["@markup.list"] = { link = "Special" },
  ["@markup.quote"] = { link = "Comment" },
  ["@diff.plus"] = { link = "Added" },
  ["@diff.minus"] = { link = "Removed" },
  ["@diff.delta"] = { link = "Changed" },

  -- ===========================================================================
  -- LSP AND DIAGNOSTICS  (the spectrum runs from violet for errors to cyan)
  -- ===========================================================================
  DiagnosticError = { fg = c.violet },
  DiagnosticWarn = { fg = c.purple },
  DiagnosticInfo = { fg = c.sky },
  DiagnosticHint = { fg = c.cyan },
  DiagnosticOk = { fg = c.blue },
  DiagnosticUnderlineError = { sp = c.violet, undercurl = true },
  DiagnosticUnderlineWarn = { sp = c.purple, undercurl = true },
  DiagnosticUnderlineInfo = { sp = c.sky, undercurl = true },
  DiagnosticUnderlineHint = { sp = c.cyan, undercurl = true },
  DiagnosticUnderlineOk = { sp = c.blue, undercurl = true },
  DiagnosticUnnecessary = { link = "Comment" },
  DiagnosticDeprecated = { strikethrough = true },
  LspReferenceText = { bg = c.gray },
  LspReferenceRead = { bg = c.gray },
  LspReferenceWrite = { bg = c.gray, bold = true },
  LspInlayHint = { fg = c.comment, italic = true },
  LspCodeLens = { fg = c.comment },
  LspSignatureActiveParameter = { fg = c.cyan, bold = true, underline = true },

  -- --- Git signs (gitsigns.nvim, mini.diff) ----------------------------------
  GitSignsAdd = { link = "Added" },
  GitSignsChange = { link = "Changed" },
  GitSignsDelete = { link = "Removed" },
}

for name, spec in pairs(groups) do
  vim.api.nvim_set_hl(0, name, spec)
end

-- =============================================================================
-- TERMINAL COLORS  (:terminal uses the Ghostty palette)
-- =============================================================================
for i = 0, 15 do
  vim.g["terminal_color_" .. i] = ({
    "{{ color0 }}", "{{ color1 }}", "{{ color2 }}", "{{ color3 }}", "{{ color4 }}", "{{ color5 }}", "{{ color6 }}", "{{ color7 }}",
    "{{ color8 }}", "{{ color9 }}", "{{ color10 }}", "{{ color11 }}", "{{ color12 }}", "{{ color13 }}", "{{ color14 }}", "{{ color15 }}",
  })[i + 1]
end
