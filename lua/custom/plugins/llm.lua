return {
  'pixqc/llm.nvim',
  dependencies = { 'nvim-neotest/nvim-nio' },
  config = function()
    local nio = require 'nio'
    local M = {}

    local timeout_ms = 1000
    local system_prompt = ''
    local service_lookup = {
      groq_l3_405b = {
        url = 'https://api.groq.com/openai/v1/chat/completions',
        model = 'llama-3.1-405b-reasoning',
        api_key_name = 'GROQ_API_KEY',
      },
      groq_l3_70b = {
        url = 'https://api.groq.com/openai/v1/chat/completions',
        model = 'llama-3.1-70b-versatile',
        api_key_name = 'GROQ_API_KEY',
      },
      groq_l3_8b = {
        url = 'https://api.groq.com/openai/v1/chat/completions',
        model = 'llama-3.1-8b-instant',
        api_key_name = 'GROQ_API_KEY',
      },
      openai = {
        url = 'https://api.openai.com/v1/chat/completions',
        model = 'gpt-4o',
        api_key_name = 'OPENAI_API_KEY',
      },
      anthropic = {
        url = 'https://api.anthropic.com/v1/messages',
        model = 'claude-3-5-sonnet-20240620',
        api_key_name = 'ANTHROPIC_API_KEY',
      },
    }

    function M.setup(opts)
      timeout_ms = opts.timeout_ms or 2500
      if opts.services then
        for key, service in pairs(opts.services) do
          service_lookup[key] = service
        end
      end
      system_prompt = opts.system_prompt or 'be brief, get to the point; when outputting code, i dont want explanation, just write the code.'

      -- Set up keymaps
      local function set_keymap(mode, key, fn, desc)
        vim.keymap.set(mode, '<leader>l' .. key, fn, { desc = desc })
      end

      set_keymap('n', 'l', function()
        M.prompt { replace = false, service = 'groq_l3_8b' }
      end, 'LLM Prompt (Groq Llama3)')
      set_keymap('v', 'l', function()
        M.prompt { replace = false, service = 'groq_l3_8b' }
      end, 'LLM Prompt (Groq Llama3) - Visual')
      set_keymap('v', 'L', function()
        M.prompt { replace = true, service = 'groq_l3_8b' }
      end, 'LLM Replace (Groq Llama3) - Visual')

      set_keymap('n', 'k', function()
        M.prompt { replace = false, service = 'groq_l3_70b' }
      end, 'LLM Prompt (Groq Llama3-70b)')
      set_keymap('v', 'k', function()
        M.prompt { replace = false, service = 'groq_l3_70b' }
      end, 'LLM Prompt (Groq Llama3-70b) - Visual')
      set_keymap('v', 'K', function()
        M.prompt { replace = true, service = 'groq_l3_70b' }
      end, 'LLM Replace (Groq Llama3-70b) - Visual')

      set_keymap('n', 'j', function()
        M.prompt { replace = false, service = 'groq_l3_405b' }
      end, 'LLM Prompt (Groq Mixtral)')
      set_keymap('v', 'j', function()
        M.prompt { replace = false, service = 'groq_l3_405b' }
      end, 'LLM Prompt (Groq Mixtral) - Visual')
      set_keymap('v', 'J', function()
        M.prompt { replace = true, service = 'groq_l3_405b' }
      end, 'LLM Replace (Groq Mixtral) - Visual')
    end

    function M.get_lines_until_cursor()
      local current_buffer = vim.api.nvim_get_current_buf()
      local current_window = vim.api.nvim_get_current_win()
      local cursor_position = vim.api.nvim_win_get_cursor(current_window)
      local row = cursor_position[1]

      local lines = vim.api.nvim_buf_get_lines(current_buffer, 0, row, true)

      return table.concat(lines, '\n')
    end

    local function write_string_at_cursor(str)
      local current_window = vim.api.nvim_get_current_win()
      local cursor_position = vim.api.nvim_win_get_cursor(current_window)
      local row, col = cursor_position[1], cursor_position[2]

      local lines = vim.split(str, '\n')
      vim.api.nvim_put(lines, 'c', true, true)

      local num_lines = #lines
      local last_line_length = #lines[num_lines]
      vim.api.nvim_win_set_cursor(current_window, { row + num_lines - 1, col + last_line_length })
    end

    local function process_data_lines(lines, service, process_data)
      for _, line in ipairs(lines) do
        local data_start = line:find 'data: '
        if data_start then
          local json_str = line:sub(data_start + 6)
          local stop = false
          if line == 'data: [DONE]' then
            return true
          end
          local data = vim.json.decode(json_str)
          if service == 'anthropic' then
            stop = data.type == 'message_stop'
          end
          if stop then
            return true
          else
            nio.sleep(5)
            vim.schedule(function()
              vim.cmd 'undojoin'
              process_data(data)
            end)
          end
        end
      end
      return false
    end

    local function process_sse_response(response, service)
      local buffer = ''
      local has_tokens = false
      local start_time = vim.uv.hrtime()

      nio.run(function()
        nio.sleep(timeout_ms)
        if not has_tokens then
          response.stdout.close()
          print 'llm.nvim has timed out!'
        end
      end)
      local done = false
      while not done do
        local current_time = vim.uv.hrtime()
        local elapsed = (current_time - start_time)
        if elapsed >= timeout_ms * 1000000 and not has_tokens then
          return
        end
        local chunk = response.stdout.read(1024)
        if chunk == nil then
          break
        end
        buffer = buffer .. chunk

        local lines = {}
        for line in buffer:gmatch '(.-)\r?\n' do
          table.insert(lines, line)
        end

        buffer = buffer:sub(#table.concat(lines, '\n') + 1)

        done = process_data_lines(lines, service, function(data)
          local content
          if service == 'anthropic' then
            if data.delta and data.delta.text then
              content = data.delta.text
            end
          else
            if data.choices and data.choices[1] and data.choices[1].delta then
              content = data.choices[1].delta.content
            end
          end
          if content and content ~= vim.NIL then
            has_tokens = true
            write_string_at_cursor(content)
          end
        end)
      end
    end

    function M.prompt(opts)
      local replace = opts.replace
      local service = opts.service
      local prompt = ''
      local visual_lines = M.get_visual_selection()
      if visual_lines then
        prompt = table.concat(visual_lines, '\n')
        if replace then
          vim.api.nvim_command 'normal! d'
          vim.api.nvim_command 'normal! k'
        else
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
        end
      else
        prompt = M.get_lines_until_cursor()
      end

      local url = ''
      local model = ''
      local api_key_name = ''

      local found_service = service_lookup[service]
      if found_service then
        url = found_service.url
        api_key_name = found_service.api_key_name
        model = found_service.model
      else
        print('invalid service: ' .. service)
        return
      end

      local api_key = api_key_name and os.getenv(api_key_name)

      local data
      if service == 'anthropic' then
        data = {
          system = system_prompt,
          messages = {
            {
              role = 'user',
              content = prompt,
            },
          },
          model = model,
          stream = true,
          max_tokens = 1024,
        }
      else
        data = {
          messages = {
            {
              role = 'system',
              content = system_prompt,
            },
            {
              role = 'user',
              content = prompt,
            },
          },
          model = model,
          temperature = 0.7,
          stream = true,
        }
      end

      local args = {
        '-N',
        '-X',
        'POST',
        '-H',
        'Content-Type: application/json',
        '-d',
        vim.json.encode(data),
      }

      if api_key then
        if service == 'anthropic' then
          table.insert(args, '-H')
          table.insert(args, 'x-api-key: ' .. api_key)
          table.insert(args, '-H')
          table.insert(args, 'anthropic-version: 2023-06-01')
        else
          table.insert(args, '-H')
          table.insert(args, 'Authorization: Bearer ' .. api_key)
        end
      end

      table.insert(args, url)

      local response = nio.process.run {
        cmd = 'curl',
        args = args,
      }
      print('querying ' .. service .. '...')
      nio.run(function()
        nio.api.nvim_command 'normal! o'
        process_sse_response(response, service)
        vim.schedule(function()
          vim.api.nvim_echo({ { '', 'Normal' } }, false, {})
        end)
      end)
    end

    function M.get_visual_selection()
      local _, srow, scol = unpack(vim.fn.getpos 'v')
      local _, erow, ecol = unpack(vim.fn.getpos '.')

      -- visual line mode
      if vim.fn.mode() == 'V' then
        if srow > erow then
          return vim.api.nvim_buf_get_lines(0, erow - 1, srow, true)
        else
          return vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
        end
      end

      -- regular visual mode
      if vim.fn.mode() == 'v' then
        if srow < erow or (srow == erow and scol <= ecol) then
          return vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
        else
          return vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {})
        end
      end

      -- visual block mode
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

    -- Setup call
    M.setup {
      system_prompt = 'be brief, get to the point; when outputting code, i dont want explanation, just write the code.',
      timeout_ms = 2500,
    }

    -- Return the module
    return M
  end,
}
