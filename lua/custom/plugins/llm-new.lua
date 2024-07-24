return {
  'pixqc/llm.nvim',
  dependencies = { 'nvim-neotest/nvim-nio' },
  config = function()
    local nio = require 'nio'
    local llm_config = {
      model = 'groq_l3_70b',
      api_key = os.getenv 'GROQ_API_KEY',
      base_url = 'https://api.groq.com/openai/v1/chat/completions',
      system_prompt = 'be brief, get to the point; when outputting code, i dont want explanation, just write the code.',
      timeout_ms = 1000,
      temperature = 0.7,
      replace = false,
    }

    local function get_visual_selection()
      local _, srow, scol = unpack(vim.fn.getpos "'<")
      local _, erow, ecol = unpack(vim.fn.getpos "'>")

      if vim.fn.mode() == 'V' then
        if srow > erow then
          return vim.api.nvim_buf_get_lines(0, erow - 1, srow, true)
        else
          return vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
        end
      end

      if vim.fn.mode() == 'v' then
        if srow < erow or (srow == erow and scol <= ecol) then
          return vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
        else
          return vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {})
        end
      end

      if vim.fn.mode() == '\22' then
        local lines = {}
        if srow > erow then
          srow, erow = erow, srow
        end
        if scol > ecol then
          scol, ecol = ecol, scol
        end
        for i = srow, erow do
          table.insert(lines, vim.api.nvim_buf_get_text(0, i - 1, math.min(scol - 1, ecol), i - 1, math.max(scol - 1, ecol), {})[1])
        end
        return lines
      end
    end

    local function get_lines_until_cursor()
      local current_buffer = vim.api.nvim_get_current_buf()
      local current_window = vim.api.nvim_get_current_win()
      local cursor_position = vim.api.nvim_win_get_cursor(current_window)
      local row = cursor_position[1]

      local lines = vim.api.nvim_buf_get_lines(current_buffer, 0, row, true)

      return table.concat(lines, '\n')
    end

    local function process_stream(response_text)
      local lines = vim.split(response_text, '\n')
      local has_tokens = false
      local start_time = vim.loop.now()

      for _, line in ipairs(lines) do
        if line:match '^data: ' then
          local json_str = line:sub(6)
          if json_str == '[DONE]' then
            return
          end
          local success, data = pcall(vim.json.decode, json_str)
          if success and data.choices and data.choices[1] and data.choices[1].delta then
            local content = data.choices[1].delta.content
            if content then
              has_tokens = true
              vim.schedule(function()
                vim.cmd 'undojoin'
                local content_lines = vim.split(content, '\n')
                vim.api.nvim_put(content_lines, 'c', true, true)
              end)
            end
          end
        end

        if vim.loop.now() - start_time > llm_config.timeout_ms * 1000 and not has_tokens then
          print 'llm.nvim has timed out!'
          return
        end
      end
    end

    local function prompt(opts)
      local config = vim.tbl_extend('force', llm_config, opts)

      local user_prompt = ''
      local visual_lines = get_visual_selection()
      if visual_lines then
        user_prompt = table.concat(visual_lines, '\n')
        if config.replace then
          vim.api.nvim_command 'normal! d'
          vim.api.nvim_command 'normal! k'
        else
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
        end
      else
        user_prompt = get_lines_until_cursor()
      end

      local data = {
        messages = {
          { role = 'system', content = config.system_prompt },
          { role = 'user', content = user_prompt },
        },
        model = config.model,
        temperature = config.temperature,
        stream = true,
      }
      local headers = {
        'Content-Type: application/json',
        'Authorization: Bearer ' .. config.api_key,
      }
      local args = {
        'curl',
        '-sS',
        '-N',
        '-X',
        'POST',
        '-H',
        headers[1],
        '-H',
        headers[2],
        '-d',
        vim.json.encode(data),
        config.base_url,
      }
      local response = nio.fn.system(args)
      print('Querying ' .. config.model .. '...')
      nio.run(function()
        vim.cmd 'normal! o'
        process_stream(response)
        vim.schedule(function()
          vim.api.nvim_echo({ { '', 'Normal' } }, false, {})
        end)
      end)
    end

    local function set_keymap(mode, key, fn, desc)
      vim.keymap.set(mode, '<leader>l' .. key, fn, { desc = desc })
    end

    local function setup_model_keymaps(key, model, name)
      local base_desc = string.format('LLM %s (Groq %s)', '%s', name)
      set_keymap('n', key, function()
        prompt { model = model, replace = false }
      end, string.format(base_desc, 'Prompt'))
      set_keymap('v', key, function()
        prompt { model = model, replace = false }
      end, string.format(base_desc, 'Prompt') .. ' - Visual')
      set_keymap('v', key:upper(), function()
        prompt { model = model, replace = true }
      end, string.format(base_desc, 'Replace') .. ' - Visual')
    end

    setup_model_keymaps('l', 'llama-3.1-8b-instant', 'Llama3.1-8b')
    setup_model_keymaps('k', 'llama-3.1-70b-versatile', 'Llama3.1-70b')
    setup_model_keymaps('j', 'llama-3.1-405b-reasoning', 'Llama3.1-405b')
  end,
}
