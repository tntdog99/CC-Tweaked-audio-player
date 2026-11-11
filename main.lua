local args = {...}
local function url_encode(str)
    if str == nil then
        return ""
    end

    str = string.gsub(str, "\n", "\r\n")
    str = string.gsub(str, "([^%w%-_%.~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
    return str
end

local function get_playlist_info(playlist_url)
    local request_url = server_url .. 'read_videos?video_url=' .. url_encode(playlist_url)
    worked, http_error = http.checkURL(request_url)
    if worked == false then
        print('HTTP ERROR: '..http_error)
        return {}
    end
    
    
    http_resp, http_error = http.get(request_url)
    if http_resp == nil then
        print('HTTP ERROR: '..http_error)
        return {}
    end
    videos = http_resp.readAll()
    return videos
end

local function format_time(time, max_time)
    formatted_time = ''
    if max_time == nil then
        max_time = time
    end
    local hours = math.floor(time / 3600)
    local minutes = math.floor((time % 3600) / 60)
    local seconds = math.floor(time % 60)

    if max_time >= 3600 then
        return string.format("%d:%02d:%02d", hours, minutes, seconds)
    elseif max_time >= 60 then
        return string.format("%d:%02d", minutes, seconds)
    else
        return string.format("%d", seconds)
    end
end

width, height = term.getSize()
server_url = args[1]
paused = true
progress = 0.0
next_up = {}
current_video_url = ''
current_play_time = 0
last_chec_unix = os.clock()
duration = 350
changed = true
last_progress_printr = ''

while true do
    delta = os.clock()-last_chec_unix
    last_chec_unix = os.clock()
    current_play_time = current_play_time + delta
    progress = current_play_time / duration

    local progress_numbers = ' '..format_time(current_play_time, duration)..'/'..format_time(duration)
    local progress_bar_offset = #progress_numbers + 2
    local filled = math.floor(progress * (width - progress_bar_offset))
    local progress_print = '['..string.rep("\127", filled)..string.rep("\128", ((width-progress_bar_offset)-filled))..']'..progress_numbers




    if progress_print ~= last_progress_printr then
        changed = true
        last_progress_printr = progress_print
    end


    -- print('running')

    -- list_info = get_playlist_info(args[2])
    -- print(textutils.serialize(list_info))

    if changed == true then
        changed = false
        term.clear()
        term.setCursorPos(1, 1)
        print(filled, width, progress_bar_offset)
        print(progress_print)
        middle_symbol = paused and '\16' or '\124 \124'
        print('<'..string.rep(' ', width/3-1)..middle_symbol..string.rep(' ', width/3-1-#middle_symbol)..'>')
    end
    sleep(0.05)
end