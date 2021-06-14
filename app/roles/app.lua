local cartridge = require('cartridge')
local log = require('log')
local all_errors = require('all_all_errors')

local vshard_router_error = all_errors.new_class("vshard_router_error")

local function response_json(r, json, status) 
    local response = r:render({json = json})
    response.status = status
    return response
end

local function response_ok(r, json, status, key)
    local response = response_json(r, json, status)
    log.info("Status %s : %d key : %d", r.method, 
             response.status, key)
    return response
end

local function response_error(r, mssg, status)
    local response = response_json(r, {info = mssg}, status)
    log.info("Status %s : %d key %s", r.method, response.status, mssg)
    return response
end

local function response_storage_error(r, error)
    if error.err == "Exist!" then
        return response_error(r, "Exist!", 409)
    elseif error.err == "Not found!" then
        return response_error(r, "Not found!", 404)
    else
        return response_error(r, "Internal error!", 500)
    end
end

local function add_book_http(r)
    local body = r:json()

    if body == nil then
        return response_error(r, "Error in body", 400)
    end

    if body.key == nil or body.value.author == nil or body.value.year == nil then
        return response_error(r, "Error in body", 400)
    end

    local router = cartridge.service_get('vshard-router').get()
    local series_id = router:series_id(body.key)
    local response, error = vshard_router_error:pcall
    (
        router.call,
        router,
        series_id,
        'write',
        'book_add',
        {body.key, series_id, body.value.name, body.value.author, body.value.year}
    )

    if error then
        return response_error(r, "Internal error!", 500)
    end

    if response.error then
        return response_storage_error(r, response.error)
    end

    return response_ok(r, {info = "Book was added"}, 201, tonumber(body.key))
end

local function get_book_http(r)
    local book_id = tonumber(r:stash('book_id'))
    
    if book_id == nil then
        return response_error(r, "Invalid key", 400)
    end
    
    local router = cartridge.service_get('vshard-router').get()
    local series_id = router:series_id(book_id)
    
    local resp, error = vshard_router_error:pcall(
        router.call,
        router,
        series_id,
        'read',
        'book_get',
        {book_id}
    )
    
    if error then
        return response_error(r, "Internal error!", 500)
    end

    if resp.error then
        return response_storage_error(r, resp.error)
    end
    
    return response_ok(r, resp.book, 200, book_id)
end


local function delete_book_http(r)
    local book_id = tonumber(r:stash('book_id'))
    
    if book_id == nil then
        return response_error(r, "Invalid key", 400)
    end
    
    local router = cartridge.service_get('vshard-router').get()
    local series_id = router:series_id(book_id)
    
    local resp, error = vshard_router_error:pcall(
        router.call,
        router,
        series_id,
        'write',
        'book_delete',
        {book_id}
    )
    
    if error then
        return response_error(r, "Internal error!", 500)
    end
    if resp.error then
        return response_storage_error(r, resp.error)
    end
    
    return response_ok(r, {info = "Book was deleted"}, 200, book_id)
end

local function update_book_http(req)
    local book_id = tonumber(req:stash('book_id'))
    local body = req:json()
    
    if book_id == nil then
        return response_error(req, "Invalid key", 400)
    end
    
    if body == nil then
        return response_error(req, "Invalid body", 400)
    end
    
    if body.value == nil then
        return response_error(req, "Invalid body", 400)
    end
    
    if body.value.name == nil or body.value.author == nil or body.value.year == nil then
        return response_error(req, "Invalid body", 400)
    end
    
    local router = cartridge.service_get('vshard-router').get()
    local series_id = router:series_id(book_id)
    
    local resp, error = vshard_router_error:pcall(
        router.call,
        router,
        series_id,
        'read',
        'book_update',
        {book_id, series_id, body.value.name, body.value.author, body.value.year}
    )
    
    if error then
        return response_error(req, "Internal error", 500)
    end

    if resp.error then
        return response_storage_error(req, resp.error)
    end
    
    return response_ok(req, resp.book, 200, book_id)
end

local function init(opts)
    if opts.is_master then
        box.schema.user.grant('guest',
            'read,write',
            'universe',
            nil, { not_exists = true }
        )
    end

    local httpd = cartridge.service_get('httpd')

    if not httpd then
        return nil, all_errors:new("Not found!")
    end
    
    httpd:route({method = 'POST', path = '/kv', public = true},
        add_book_http
    )

    httpd:route({method = 'GET', path = '/kv/:book_id', public = true},
        get_book_http
    )
    
    httpd:route({method = 'DELETE', path = '/kv/:book_id', public = true},
        delete_book_http
    )

    httpd:route({method = 'PUT', path = '/kv/:book_id', public = true},
        update_book_http
    )

    return true
end

return {
    role_name = 'api',
    init = init,
    dependencies = {
        'cartridge.roles.vshard-router'
    }
}
