local args = {...}

dfpwm = require('cc.audio.dfpwm')

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

local function safe_http(url, headers, binary)
    if headers == nil then 
        headers = nil
    end
    if binary == nil then 
        binary = false
    end

    local worked, http_error = http.checkURL(url)
    if worked == false then
        print('HTTP ERROR: '..http_error)
        return false, {}
    end
    
    local http_resp, http_error = http.get(url, headers, binary)
    if http_resp == nil then
        print('HTTP ERROR: '..http_error)
        return false, {}
    end
    return true, http_resp
end

local function get_playlist_info(playlist_url)
    local request_url = server_url .. 'read_videos?video_url=' .. url_encode(playlist_url)

    local worked, http_resp = safe_http(request_url)
    if worked == false then
        return nil
    end
    local videos = http_resp.readAll()
    http_resp.close()
    return textutils.unserializeJSON(videos)
end

local function get_next_url(playlist_url)
    local request_url = server_url .. 'next_url?video_url=' .. url_encode(playlist_url)

    local worked, http_resp = safe_http(request_url)
    if worked == false then
        return nil
    end
    local next_url = http_resp.readAll()
    http_resp.close()
    return textutils.unserializeJSON(next_url)
end

local function download_chunk(url, chunk_stuff, chunk_id)
    local request_url = server_url .. 'chunk_download?video_url=' .. url_encode(url) ..'&start_time='..chunk_stuff[1]..'&end_time='..chunk_stuff[2]

    local worked, http_resp = safe_http(request_url, nil, true)
    if worked == false then
        return nil
    end
    local dfpwm_data = http_resp.readAll()
    http_resp.close()
    return dfpwm_data
end

local function get_chunked_dur(video_details)
    local chunks = {}
    for chunk = 0, video_details['duration'], 2 do
        table.insert(chunks, {chunk, chunk+2})
    end
    return chunks
end

local function format_time(time, max_time)
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
seek_id = 0
progress = 0.0
next_up = {args[2]}
current_video_url = args[2]
current_play_time = 0
last_chec_unix = os.epoch("utc")/1000
duration = -1
changed = true
last_progress_printr = ''
audio_chunk_look_ups = {}
loaded_audio_chunks = {}
current_audio_chunk = 1

next_up = get_playlist_info(current_video_url)
print(textutils.serialize(next_up[1]))
audio_chunk_look_ups = get_chunked_dur(next_up[1])
current_audio_chunk = 1
duration = next_up[1]['duration']
current_play_time = 0
loaded_audio_chunks = {}
playing_chunk = nil

speaker = peripheral.find("speaker")


local function update_loop()
    while true do
        local delta = os.epoch("utc")/1000-last_chec_unix
        last_chec_unix = os.epoch("utc")/1000

        -- only update progress while umpaused
        if paused == false then
            current_play_time = current_play_time + delta
            progress = current_play_time / duration
        end

        local progress_numbers = ' '..format_time(current_play_time, duration)..'/'..format_time(duration)
        local progress_bar_offset = #progress_numbers + 2
        local filled = math.floor(progress * (width - progress_bar_offset))
        local progress_print = '['..string.rep("\127", filled)..string.rep("\128", ((width-progress_bar_offset)-filled))..']'..progress_numbers


        -- update current video
        if current_play_time > duration then
            current_video_url = get_next_url(current_video_url)
            if current_video_url == nil then
                break
            end
            local updated_playlist = get_playlist_info(current_video_url)
            if not updated_playlist or not updated_playlist[1] then
                break
            end
            seek_id = seek_id + 1
            speaker.stop()
            os.queueEvent("speaker_audio_empty")
            next_up = updated_playlist
            audio_chunk_look_ups = get_chunked_dur(next_up[1])
            current_audio_chunk = 1
            duration = next_up[1]['duration']
            current_play_time = 0
            loaded_audio_chunks = {}
            playing_chunk = nil

        end

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
            print(progress_print)
            middle_symbol = paused and '\16' or '\124 \124'
            print(next_up[1]['title'])
            print(' <'..string.rep(' ', width/2-2)..middle_symbol..string.rep(' ', width/2-2-#middle_symbol)..'>')
            print(current_audio_chunk)

        end
        sleep(0.05)
    end
end

playing_chunk = nil

local function audio_loop()
    while true do
        local chunk = loaded_audio_chunks[current_audio_chunk]
        if paused == false and chunk ~= nil then

            local current_seek = seek_id
            local current_index = current_audio_chunk
            
            local decoder = dfpwm.make_decoder() 
            local decoded = decoder(chunk)

            while not paused and current_seek == seek_id and not speaker.playAudio(decoded) do
                os.pullEvent("speaker_audio_empty")
            end

            if not paused and current_seek == seek_id then
                playing_chunk = current_index
                current_audio_chunk = current_index + 1
            end
        else
            sleep(0.05)
        end
    end
end




local function key_loop()
    while true do
        local event, key, is_held = os.pullEvent("key")
        if key == keys.space then
            paused = not paused
            if paused then
                seek_id = seek_id + 1
                speaker.stop()
                if playing_chunk then
                    current_audio_chunk = math.max(1, playing_chunk - 1)
                    current_play_time = (current_audio_chunk - 1) * 2
                end
                os.queueEvent("speaker_audio_empty")
            end
        end
        if key == keys.left then
            if current_audio_chunk == 1 then
                
            else
                seek_id = seek_id + 1
                speaker.stop()
                current_audio_chunk = math.max(1, playing_chunk - 2)
                current_play_time = (current_audio_chunk - 1) * 2

                os.queueEvent("speaker_audio_empty")
            end
        end
        if key == keys.right then
            seek_id = seek_id + 1
            speaker.stop()
            current_audio_chunk = math.max(1, playing_chunk + 2)
            current_play_time = (current_audio_chunk - 1) * 3
            os.queueEvent("speaker_audio_empty")
        end
    end
end




prefetch_amount = 3
local function downloader()
    while true do
        
        if current_audio_chunk > 2 then
            loaded_audio_chunks[current_audio_chunk-2] = nil
        end
        for i = 0, prefetch_amount do
            if current_audio_chunk+i <= #audio_chunk_look_ups then
                if loaded_audio_chunks[current_audio_chunk+i] == nil then
                    loaded_audio_chunks[current_audio_chunk+i] = download_chunk(next_up[1]['url'], audio_chunk_look_ups[current_audio_chunk+i], current_audio_chunk+i)
                end
            end
        end
        sleep(0.05)
    end

end
local function pre_fetch()
    while true do
        if next_up[2] ~= nil then
            download_chunk(next_up[2]['url'], {0,2}, 0)
        else
            sleep(60)
        end
        
        
        sleep(10)
    end

end
parallel.waitForAny(audio_loop, update_loop, key_loop, downloader, pre_fetch)
print('Done')