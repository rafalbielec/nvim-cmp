local window = require('cmp.utils.window')
local config = require('cmp.config')

---@class cmp.DocsView
---@field public window cmp.Window
local docs_view = {}

---Create new floating window module
docs_view.new = function()
  local self = setmetatable({}, { __index = docs_view })
  self.entry = nil
  self.window = window.new()
  self.window:option('conceallevel', 2)
  self.window:option('concealcursor', 'n')
  self.window:option('foldenable', false)
  self.window:option('linebreak', true)
  self.window:option('scrolloff', 0)
  self.window:option('showbreak', 'NONE')
  self.window:option('wrap', true)
  self.window:buffer_option('filetype', 'cmp_docs')
  self.window:buffer_option('buftype', 'nofile')
  return self
end

docs_view.markdownToPlainText = function(markdownTable)
  local plainTextTable = {}

  for _, markdown in ipairs(markdownTable) do
    -- Start with the original string
    local plainText = markdown

    -- Remove code fences and language specifiers (e.g., ```csharp)
    plainText = plainText:gsub('```[%w]*\n?', '')
    plainText = plainText:gsub('```', '')

    -- Remove inline code
    plainText = plainText:gsub('`(.-)`', '%1')

    -- Remove emphasis (bold, italic)
    plainText = plainText:gsub('%*%*([^%*]+)%*%*', '%1') -- Bold (**text**)
    plainText = plainText:gsub('%_%_([^%_]+)%_%_', '%1') -- Bold (__text__)
    plainText = plainText:gsub('%*([^%*]+)%*', '%1') -- Italic (*text*)
    plainText = plainText:gsub('%_([^%_]+)%_', '%1') -- Italic (_text_)

    -- Remove strikethrough
    plainText = plainText:gsub('~~(.-)~~', '%1')

    -- Remove links but keep the text
    plainText = plainText:gsub('%[([^%]]+)%]%([^%)]+%)', '%1')

    -- Remove images but keep the alt text
    plainText = plainText:gsub('!%[([^%]]+)%]%([^%)]+%)', '%1')

    -- Decode HTML entities like &nbsp; (replacing just common ones)
    plainText = plainText:gsub('&nbsp;', ' ')
    plainText = plainText:gsub('&lt;', '<')
    plainText = plainText:gsub('&gt;', '>')
    plainText = plainText:gsub('&amp;', '&')

    -- Remove blockquotes
    plainText = plainText:gsub('^>+', '')

    -- Remove lists
    plainText = plainText:gsub('^%s*[-*+]%s+', '')
    plainText = plainText:gsub('^%s*%d+%.%s+', '')

    -- Remove escaped characters (e.g., "\)")
    plainText = plainText:gsub('\\(%p)', '%1')

    -- Strip extra newlines or whitespace from the edges
    plainText = plainText:gsub('^%s+', ''):gsub('%s+$', '')

    -- Add cleaned text to the result table
    table.insert(plainTextTable, plainText)
  end

  return plainTextTable
end

---Open documentation window
---@param e cmp.Entry
---@param view cmp.WindowStyle
docs_view.open = function(self, e, view)
  local documentation = config.get().window.documentation
  if not documentation then
    return
  end

  if not e or not view then
    return self:close()
  end

  local border_info = window.get_border_info({ style = documentation })
  local right_space = vim.o.columns - (view.col + view.width) - 1
  local left_space = view.col - 1
  local max_width = math.max(left_space, right_space)
  if documentation.max_width > 0 then
    max_width = math.min(documentation.max_width, max_width)
  end

  -- Update buffer content if needed.
  if not self.entry or e.id ~= self.entry.id then
    local documents = e:get_documentation()
    if #documents == 0 then
      return self:close()
    end

    self.entry = e
    vim.api.nvim_buf_call(self.window:get_buffer(), function()
      vim.cmd([[syntax clear]])
      vim.api.nvim_buf_set_lines(self.window:get_buffer(), 0, -1, false, {})
    end)
    local opts = {
      max_width = max_width - border_info.horiz,
    }
    if documentation.max_height > 0 then
      opts.max_height = documentation.max_height
    end

    local bufnr = self.window:get_buffer()
    local md = self.markdownToPlainText(documents)
    local cleanedTable = {}

    -- remove empty strings which translate into new lines in the pop-up
    for _, value in ipairs(md) do
      if value ~= '' then
        table.insert(cleanedTable, value)
      end
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, cleanedTable)

    -- replaced this invocation
    -- vim.lsp.util.stylize_markdown(self.window:get_buffer(), documents, opts)
  end

  -- Set buffer as not modified, so it can be removed without errors
  vim.api.nvim_buf_set_option(self.window:get_buffer(), 'modified', false)

  -- Calculate window size.
  local opts = {
    max_width = max_width - border_info.horiz,
  }
  if documentation.max_height > 0 then
    opts.max_height = documentation.max_height - border_info.vert
  end
  local width, height = vim.lsp.util._make_floating_popup_size(vim.api.nvim_buf_get_lines(self.window:get_buffer(), 0, -1, false), opts)
  if width <= 0 or height <= 0 then
    return self:close()
  end

  -- Calculate window position.
  local right_col = view.col + view.width
  local left_col = view.col - width - border_info.horiz
  local col, left
  if right_space >= width and left_space >= width then
    if right_space < left_space then
      col = left_col
      left = true
    else
      col = right_col
    end
  elseif right_space >= width then
    col = right_col
  elseif left_space >= width then
    col = left_col
    left = true
  else
    return self:close()
  end

  -- Render window.
  self.window:option('winblend', documentation.winblend)
  self.window:option('winhighlight', documentation.winhighlight)
  local style = {
    relative = 'editor',
    style = 'minimal',
    width = width,
    height = height,
    row = view.row,
    col = col,
    border = documentation.border,
    zindex = documentation.zindex or 50,
  }
  self.window:open(style)

  -- Correct left-col for scrollbar existence.
  if left then
    style.col = style.col - self.window:info().scrollbar_offset
    self.window:open(style)
  end
end

---Close floating window
docs_view.close = function(self)
  self.window:close()
  self.entry = nil
end

docs_view.scroll = function(self, delta)
  if self:visible() then
    local info = vim.fn.getwininfo(self.window.win)[1] or {}
    local top = info.topline or 1
    top = top + delta
    top = math.max(top, 1)
    top = math.min(top, self.window:get_content_height() - info.height + 1)

    vim.defer_fn(function()
      vim.api.nvim_buf_call(self.window:get_buffer(), function()
        vim.api.nvim_command('normal! ' .. top .. 'zt')
        self.window:update()
      end)
    end, 0)
  end
end

docs_view.visible = function(self)
  return self.window:visible()
end

return docs_view
