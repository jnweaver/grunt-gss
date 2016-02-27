module.exports = (grunt) ->

  csv2json = require './lib/csv2json'
  done = undefined
  extend = require 'deep-extend'
  google = require 'googleapis'
  http = require 'http'
  open = require 'open'
  request = require 'request'
  toType = (o) -> ({}).toString.call(o).match(/\s([a-zA-Z]+)/)[1].toLowerCase()

  getCsv = (id, secret, fileId, gid, callback) ->
    getAuth id, secret, 'http://localhost:4477/', 'offline',
    'https://www.googleapis.com/auth/drive.readonly', (auth) ->
      getFile auth, fileId, (file) ->
        getSheet auth, file, gid, callback


  _sheets = {}
  getSheet = (auth, file, gid, callback) ->
    grunt.verbose.write 'export...'
    uri = file['exportLinks']['text/csv'] + '&gid=' + gid
    if not _sheets[uri]
      headers = Authorization: "Bearer #{auth.credentials.access_token}"
      request {uri, headers}, (err, sheet) ->
        if err and err.message
          grunt.log.error err.message
          done false
        else callback _sheets[uri] = sheet.body
    else callback _sheets[uri]

  _files = {}
  getFile = (auth, fileId, callback) ->
    grunt.verbose.write 'drive...'
    if not _files[fileId]
      drive = google.drive {version: 'v2', auth}
      drive.files.get {fileId}, (err, file) ->
        if err and err.message
          grunt.log.error err.message
          done false
        else callback _files[fileId] = file
    else callback _files[fileId]

  _auths = {}
  getAuth = (id, secret, redirect, access_type, scope, callback) ->
    grunt.verbose.write 'auth...'
    if not _auths[id]
      client = _auths[id] = new google.auth.OAuth2 id, secret, redirect
      getAccessToken client.generateAuthUrl({access_type, scope}), (code) ->
        client.getToken code, (err, tokens) ->
          if err and err.message
            grunt.log.error err.message
            done false
          else
            client.setCredentials tokens
            callback _auths[id] = client
    else callback _auths[id]

  getAccessToken = (url, callback) ->
    grunt.verbose.write 'token...'
    open url
    server = http.createServer (req, rep) ->
      rep.end()
      req.connection.destroy()
      server.close()
      callback req.url.substr 7
    server.maxConnections = 1
    server.listen 4477 # ggss

  rxFileIdAndGid = /^.*[\/\=]([-?\w]{44}).*gid=(\d+).*$/i
  rxTrue = /^true$/i
  grunt.registerMultiTask 'gss', ->

    done = @async()
    data = @data

    (next = (file, files) ->

      # extend file
      matches = file.src[0].match rxFileIdAndGid
      fileId = matches[1]
      gid = matches[2]
      opts = extend {}, data.options, file.options or {}

      grunt.log.write "Processing #{file.dest}..."
      getCsv opts.clientId, opts.clientSecret, fileId, gid, (out) ->

        # json
        if opts.json
          grunt.log.write 'parse...'
          out = JSON.parse csv2json out

          # mapping
          if opts.mapping
            grunt.log.write 'map...'
            cols = []
            types = []
            for col, type of opts.mapping
              cols.push col
              types.push type
            for row in out
              for type, i in types
                col = cols[i]
                val = row[col]

                # convert
                if toType(type) is 'function'
                  row[col] = type val, row
                else if toType(val) isnt type
                  if type is 'array' then row[col] =
                    if not val then []
                    else if val.indexOf(',') isnt -1 then val.split ','
                    else [val]
                  else if type is 'boolean' then row[col] = rxTrue.test val
                  else if type is 'number' then row[col] = parseFloat val or 0
                  else if type is 'undefined' then delete row[col]

          # prettify
          if opts.json and opts.prettify
            grunt.log.write 'prettify...'
            out = JSON.stringify out, null, 2

        # wrap
        if toType(opts.wrap) is 'function'
          grunt.log.write 'wrap...'
          out = opts.wrap out

        # write
        grunt.log.write 'write...'
        grunt.file.write file.dest, out

        grunt.log.ok()

        # loop
        if not files.length then done true
        else next files.shift().orig, files

    ) @files.shift().orig, @files

    null

  null
