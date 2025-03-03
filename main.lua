local function setup(_, options)
	options = options or {}

	-- Configuration settings
	local config = {
		show_branch = options.show_branch == nil and true or options.show_branch,
		branch_prefix = options.branch_prefix or "on",
		branch_symbol = options.branch_symbol or "",
		branch_borders = options.branch_borders or "",
		commit_symbol = options.commit_symbol or "@",
		show_behind_ahead = options.behind_ahead == nil and true or options.behind_ahead,
		behind_symbol = options.behind_symbol or "⇣",
		ahead_symbol = options.ahead_symbol or "⇡",
		show_stashes = options.show_stashes == nil and true or options.show_stashes,
		stashes_symbol = options.stashes_symbol or "$",
		show_state = options.show_state == nil and true or options.show_state,
		show_state_prefix = options.show_state_prefix == nil and true or options.show_state_prefix,
		state_symbol = options.state_symbol or "~",
		show_staged = options.show_staged == nil and true or options.show_staged,
		staged_symbol = options.staged_symbol or "+",
		show_unstaged = options.show_unstaged == nil and true or options.show_unstaged,
		unstaged_symbol = options.unstaged_symbol or "!",
		show_untracked = options.show_untracked == nil and true or options.show_untracked,
		untracked_symbol = options.untracked_symbol or "?",
		show_commit_message = options.show_commit_message == nil and true or options.show_commit_message,
		commit_message_prefix = options.commit_message_prefix or ": ",
		commit_message_max_length = options.commit_message_max_length or 50,
	}

	-- Theme settings
	local theme = options.theme or {}
	theme = {
		prefix_color = theme.prefix_color or "white",
		branch_color = theme.branch_color or "green",
		commit_color = theme.commit_color or "bright magenta",
		behind_color = theme.behind_color or "bright magenta",
		ahead_color = theme.ahead_color or "bright magenta",
		stashes_color = theme.stashes_color or "bright magenta",
		state_color = theme.state_color or "red",
		staged_color = theme.staged_color or "bright yellow",
		unstaged_color = theme.unstaged_color or "bright orange",
		untracked_color = theme.untracked_color or "green",
		commit_message_color = theme.commit_message_color or "bright white",
	}

	-- State management (similar to git.yazi)
	local st = {
		current_path = "",
		is_git_repo = false,
		status = nil,
		stashes = nil,
		commit_msg = nil,
		last_update = 0,
	}

	-- Check if a path is within a .git directory or is a .git file/directory
	local function is_git_related_path(path)
		if not path then
			return false
		end
		return path:match("%.git/?$") or path:match("%.git/")
	end

	-- Check if current directory is git-related
	local function should_skip_git_ops()
		if not cx or not cx.active then
			return true
		end

		-- Check current directory
		local current_path = tostring(cx.active.current.cwd)
		if is_git_related_path(current_path) then
			return true
		end

		-- Check hovered item
		local hovered = cx.active.current.hovered
		if hovered and is_git_related_path(tostring(hovered.url.pure)) then
			return true
		end

		return false
	end

	-- Clear git data (similar to git.yazi's remove function)
	local clear_git_data = ya.sync(function()
		st.is_git_repo = false
		st.status = nil
		st.stashes = nil
		st.commit_msg = nil
		ya.render()
	end)

	-- Update git data (similar to git.yazi's add function)
	local update_git_data = ya.sync(function()
		if should_skip_git_ops() then
			if st.is_git_repo then
				clear_git_data()
			end
			return
		end

		local current_path = tostring(cx.active.current.cwd)

		-- Check if path changed
		if current_path ~= st.current_path then
			st.current_path = current_path
			st.is_git_repo = false -- Reset until we confirm
		end

		-- Check if this is a git repository
		local is_git_repo = false
		local success = pcall(function()
			local handle = io.popen("git rev-parse --is-inside-work-tree 2>/dev/null")
			if handle then
				local result = handle:read("*a"):gsub("[\n\r]*$", "")
				handle:close()
				is_git_repo = (result == "true")
			end
		end)

		if not success or not is_git_repo then
			if st.is_git_repo then -- Only clear if state was previously a repo
				clear_git_data()
			end
			return
		end

		-- Now we know we're in a git repo
		st.is_git_repo = true

		-- Fetch git status
		success = pcall(function()
			local handle = io.popen(
				"LANGUAGE=en_US.UTF-8 git status --ignore-submodules=dirty --branch --show-stash --ahead-behind 2>/dev/null"
			)
			if handle then
				st.status = handle:read("*a") or ""
				handle:close()
			end
		end)

		-- Fetch stashes if needed
		if config.show_stashes then
			pcall(function()
				local handle = io.popen("git stash list 2>/dev/null | wc -l")
				if handle then
					st.stashes = handle:read("*a"):gsub("[\n\r]*$", ""):gsub("^%s*(.-)%s*$", "%1")
					handle:close()
				end
			end)
		end

		-- Fetch commit message if needed
		if config.show_commit_message then
			pcall(function()
				local handle = io.popen("git log -1 --pretty=%s 2>/dev/null")
				if handle then
					local msg = handle:read("*a"):gsub("[\n\r]*$", "") or ""
					handle:close()

					if msg and msg ~= "" then
						if #msg > config.commit_message_max_length then
							msg = msg:sub(1, config.commit_message_max_length) .. "..."
						end
						st.commit_msg = msg
					end
				end
			end)
		end

		st.last_update = os.time()
		ya.render()
	end)

	-- Parse branch information from git status
	local function get_branch(status)
		if not status or status == "" then
			return {}
		end

		local branch = status:match("On branch (%S+)")

		if branch == nil then
			local commit = status:match("onto (%S+)") or status:match("detached at (%S+)")

			if commit == nil then
				return {}
			else
				local branch_prefix = config.branch_prefix == "" and " " or " " .. config.branch_prefix .. " "
				local commit_prefix = config.commit_symbol == "" and "" or config.commit_symbol

				return { "commit", branch_prefix .. commit_prefix, commit }
			end
		else
			local branch_prefix = config.branch_prefix == "" and " " or " " .. config.branch_prefix .. " "
			local branch_symbol = config.branch_symbol == "" and "" or config.branch_symbol
			local branch_borders = config.branch_borders

			if #branch_borders > 0 then
				branch = branch_borders:sub(1, 1) .. branch .. branch_borders:sub(2, 2)
			end

			if branch_symbol ~= "" then
				branch = branch_symbol .. " " .. branch
			end

			return { "branch", branch_prefix, branch }
		end
	end

	-- Other parsing functions
	local function get_behind_ahead(status)
		if not status or status == "" then
			return { "", "" }
		end

		local behind_str = status:match("Your branch is behind %S+ by (%d+) commit")
		local ahead_str = status:match("Your branch is ahead of %S+ by (%d+) commit")
		local behind_ahead_str =
			status:match("Your branch and %S+ have diverged[\r\n]%s*and have (%d+) and (%d+) different commit")

		local behind = ""
		local ahead = ""

		if behind_str ~= nil then
			behind = " " .. config.behind_symbol .. behind_str
		end

		if ahead_str ~= nil then
			ahead = " " .. config.ahead_symbol .. ahead_str
		end

		if behind_ahead_str ~= nil then
			behind = " "
				.. config.behind_symbol
				.. (status:match("Your branch and %S+ have diverged[\r\n]%s*and have (%d+)") or "")
			ahead = " "
				.. config.ahead_symbol
				.. (status:match("Your branch and %S+ have diverged[\r\n]%s*and have %d+ and (%d+)") or "")
		end

		return { behind, ahead }
	end

	local function get_stashes()
		if not st.stashes or st.stashes == "" or st.stashes == "0" then
			return ""
		else
			return " " .. config.stashes_symbol .. st.stashes
		end
	end

	local function get_state(status)
		if not status or status == "" then
			return ""
		end

		local rebase = status:match("rebase in progress")
		local merge = status:match("You have unmerged")
		local cherry = status:match("cherry%-pick")
		local bisect = status:match("bisect")

		local prefix = config.show_state_prefix and " " .. config.state_symbol or " "

		if rebase ~= nil then
			return prefix .. "rebase"
		elseif merge ~= nil then
			return prefix .. "merge"
		elseif cherry ~= nil then
			return prefix .. "cherry-pick"
		elseif bisect ~= nil then
			return prefix .. "bisect"
		else
			return ""
		end
	end

	local function get_staged(status)
		if not status or status == "" then
			return ""
		end

		local count = 0
		for line in status:gmatch("[^\r\n]+") do
			if line:match("^[AMD]%s+") or line:match("^R%s+") then
				count = count + 1
			end
		end

		if count == 0 then
			return ""
		else
			return " " .. config.staged_symbol .. count
		end
	end

	local function get_unstaged(status)
		if not status or status == "" then
			return ""
		end

		local count = 0
		for line in status:gmatch("[^\r\n]+") do
			if line:match("^%s[MD]") then
				count = count + 1
			end
		end

		if count == 0 then
			return ""
		else
			return " " .. config.unstaged_symbol .. count
		end
	end

	local function get_untracked(status)
		if not status or status == "" then
			return ""
		end

		local count = 0
		local in_untracked = false

		for line in status:gmatch("[^\r\n]+") do
			if line:match("Untracked files:") then
				in_untracked = true
			elseif in_untracked and line:match("^%s%s%S") then
				count = count + 1
			elseif in_untracked and (line:match("^$") or line:match("%(use")) then
				break
			end
		end

		if count == 0 then
			return ""
		else
			return " " .. config.untracked_symbol .. count
		end
	end

	-- Setup event handlers
	local function setup_event_handlers()
		ya.sync(function()
			-- Update git data on CD
			ps.sub("cd", function()
				clear_git_data()
				-- Using pcall to ensure errors don't crash Yazi
				pcall(function()
					-- We need a small delay to let the directory change complete
					ya.later(0.1, update_git_data)
				end)
			end)

			-- Initial update
			update_git_data()
		end)()
	end

	-- Set up events
	setup_event_handlers()

	-- Header component for Yazi
	function Header:githead()
		-- Check if we need an update
		if not st.is_git_repo or st.status == nil then
			-- Try to update if we're in a new location
			if cx and cx.active and tostring(cx.active.current.cwd) ~= st.current_path then
				update_git_data()
			end

			-- If still no data, return empty line
			if not st.is_git_repo or st.status == nil then
				return ui.Line({})
			end
		end

		local status = st.status
		local branch_array = get_branch(status)

		-- If no branch info (not in a git repo), return empty line
		if not branch_array or #branch_array == 0 then
			return ui.Line({})
		end

		local prefix = ui.Span(config.show_branch and branch_array[2] or ""):fg(theme.prefix_color)
		local branch = ui.Span(config.show_branch and branch_array[3] or "")
			:fg(branch_array[1] == "commit" and theme.commit_color or theme.branch_color)

		-- Add commit message display
		local commit_msg_span = ui.Span("")
		if config.show_commit_message and st.commit_msg then
			commit_msg_span = ui.Span(config.commit_message_prefix .. st.commit_msg):fg(theme.commit_message_color)
		end

		local behind_ahead = get_behind_ahead(status)
		local behind = ui.Span(config.show_behind_ahead and behind_ahead[1] or ""):fg(theme.behind_color)
		local ahead = ui.Span(config.show_behind_ahead and behind_ahead[2] or ""):fg(theme.ahead_color)
		local stashes = ui.Span(config.show_stashes and get_stashes() or ""):fg(theme.stashes_color)
		local state = ui.Span(config.show_state and get_state(status) or ""):fg(theme.state_color)
		local staged = ui.Span(config.show_staged and get_staged(status) or ""):fg(theme.staged_color)
		local unstaged = ui.Span(config.show_unstaged and get_unstaged(status) or ""):fg(theme.unstaged_color)
		local untracked = ui.Span(config.show_untracked and get_untracked(status) or ""):fg(theme.untracked_color)

		return ui.Line({ prefix, branch, commit_msg_span, behind, ahead, stashes, state, staged, unstaged, untracked })
	end

	-- Register with Header
	Header:children_add(Header.githead, 2000, Header.LEFT)

	-- Register with Yatline if available
	if Yatline ~= nil then
		function Yatline.coloreds.get:githead()
			-- Check if we need an update
			if not st.is_git_repo or st.status == nil then
				-- Try to update if we're in a new location
				if cx and cx.active and tostring(cx.active.current.cwd) ~= st.current_path then
					update_git_data()
				end

				-- If still no data, return empty string
				if not st.is_git_repo or st.status == nil then
					return ""
				end
			end

			local status = st.status

			-- If not in a git repo, return empty string
			if not status or status == "" then
				return ""
			end

			local githead = {}

			-- Branch information
			local branch = config.show_branch and get_branch(status) or {}
			if branch and #branch > 0 then
				table.insert(githead, { branch[2], theme.prefix_color })
				if branch[1] == "commit" then
					table.insert(githead, { branch[3], theme.commit_color })
				else
					table.insert(githead, { branch[3], theme.branch_color })
				end
			end

			-- Commit message
			if config.show_commit_message and st.commit_msg then
				table.insert(githead, { config.commit_message_prefix .. st.commit_msg, theme.commit_message_color })
			end

			-- Behind/ahead information
			local behind_ahead = config.show_behind_ahead and get_behind_ahead(status) or { "", "" }
			if behind_ahead[1] and behind_ahead[1] ~= "" then
				table.insert(githead, { behind_ahead[1], theme.behind_color })
			end
			if behind_ahead[2] and behind_ahead[2] ~= "" then
				table.insert(githead, { behind_ahead[2], theme.ahead_color })
			end

			-- Stashes
			local stashes = config.show_stashes and get_stashes() or ""
			if stashes and stashes ~= "" then
				table.insert(githead, { stashes, theme.stashes_color })
			end

			-- State
			local state = config.show_state and get_state(status) or ""
			if state and state ~= "" then
				table.insert(githead, { state, theme.state_color })
			end

			-- Staged
			local staged = config.show_staged and get_staged(status) or ""
			if staged and staged ~= "" then
				table.insert(githead, { staged, theme.staged_color })
			end

			-- Unstaged
			local unstaged = config.show_unstaged and get_unstaged(status) or ""
			if unstaged and unstaged ~= "" then
				table.insert(githead, { unstaged, theme.unstaged_color })
			end

			-- Untracked
			local untracked = config.show_untracked and get_untracked(status) or ""
			if untracked and untracked ~= "" then
				table.insert(githead, { untracked, theme.untracked_color })
			end

			if #githead == 0 then
				return ""
			else
				table.insert(githead, { " ", theme.prefix_color })
				return githead
			end
		end
	end
end

return { setup = setup }
