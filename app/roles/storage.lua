local all_errors = require('all_errors')
local checks = require('checks')
local storage_error = all_errors.new_class("Storage error")

local function init_space()
    local space = box.schema.space.create(
        'book',
        {
            format = {
                {'book_id', 'unsigned'},
                {'series_id', 'unsigned'},
                {'name', 'string'},
                {'author', 'string'},
                {'year', 'unsigned'}
            },

            not_exists = true,
        }
    )

    space:create_index('book_id', {
        parts = {'book_id'},
        not_exists = true,
    })

    space:create_index('series_id', {
        parts = {'book_id'},
        unique = false,
        not_exists = true,
    })
end


local function book_add(book_id, series_id, name, author, year)
    checks('number', 'number', 'string', 'string', 'number')
    
    local book = box.space.book:get(book_id)
    
    if book ~= nil then
        return {ok = false, error = storage_error:new("Exist!")}
    end
    
    box.space.book:insert({book_id, series_id, name, author, year})
    
    return {ok = true, error = nil}
end

local function book_delete(book_id)
    checks('number')
    
    local book = box.space.book:get(book_id)
    if book == nil then
        return {ok = false, error = storage_error:new("Not found!")}
    end
    
    box.space.book:delete(book_id)
    
    return {ok = true, error = nil}
end

local function book_get(book_id)
    checks('number')
    
    local book = box.space.book:get(book_id)
    
    if book == nil then
        return {book = nil, error = storage_error:new("Not found!")}
    end
    
    book = book:tomap({names_only = true})
    
    book.series_id = nil
    
    return {book = book, error = nil}
end

local function book_update(book_id, series_id, name, author, year)
    checks('number', 'number', 'string', 'string', 'number')
    
    local book = box.space.book:get(book_id)
    
    if book == nil then
        return {book = nil, error = storage_error:new("Not found")}
    end
    
    book = box.space.book:update(book_id, {{'=', 3, name}, {'=', 4, author}, {'=', 5, year}})
    book = book:tomap({names_only = true})
    
    book.series_id = nil
    
    return {book = book, error = nil}
end

local exported_functions = {
    book_add = book_add,
    book_delete = book_delete,
    book_get = book_get,
    book_update = book_update,
}


local function init(opts)
    if opts.is_master then
        init_space()
        
        for name in pairs(exported_functions) do
            box.schema.func.create(name, {not_exists = true})
        end
    end
    
    for name, func in pairs(exported_functions) do
        rawset(_G, name, func)
    end
    
    return true
    
end

return {
    role_name = 'storage',
    init = init,
    utils = {
        book_add = book_add,
        book_update = book_update,
        book_get = book_get,
        book_delete = book_delete,
    },
    dependencies = {
        'cartridge.roles.vshard-storage'
    }
}