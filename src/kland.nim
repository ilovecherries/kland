# This is just an example to get you started. A typical binary package
# uses this file as the main entry point of the application.

import jester, htmlgen
import system

import norm/[sqlite]
import options
import re
import strutils
import strformat
import model
import json



# i assume this just makes an sqlite db in memory
let dbConn* = open(":memory", "", "", "")
dbConn.createTables(newPost())
dbConn.createTables(newThread())

var examplePost = newPost("Hello, !!!!!")
dbConn.insert examplePost
  
routes:
  get "/":
    resp "Hello, World!"
    
  # this is just for a test
  get re"^\/post/([0-9]+)$":
    let id = parseInt(request.matches[0])
    var posts = @[newPost()]
    dbConn.select(posts, "Post.id = ?", id)
    for i in posts:
      echo i[]
    resp fmt"check console"
    
  get re"^\/threads/([0-9]+)$":
    let thread = parseInt(request.matches[0])
    resp fmt"This is thread {thread}"

  # create new thread
  post "/threads/":
    var data: JsonNode
    try:
      data = parseJson(@"payload")
      var (thread, post) = newThreadFromJSON(data)
      dbConn.insert thread
      # does this get modified? is that why it needs to be a var?
      echo thread.id

    except ModelCreateError:
      resp Http400, getCurrentExceptionMsg()
    except JsonParsingError:
      echo getCurrentExceptionMsg()
      resp Http400, "Invalid JSON."
    except:
      resp Http400, "Unknown JSON parsing error."

  # create new post in thread
  post re"^\/threads/([0-9]+)$":
    let threadId = parseInt(request.matches[0])
    # check if the thread exists in this block
    block:
      if threadId < 1:
        resp Http400, "The thread ID must be larger than zero."
      
      var threads = @[newThread()]
      dbConn.select(threads, "Thread.id = ?", threadId)
      if threads.len() == 0:
        resp Http400, fmt"The thread ID {threadId} does not exist"

    var data: JsonNode
    try:
      data = parseJson(@"payload")
      var p = newPostFromJSON(threadId, data)
      dbConn.insert p
    except ModelCreateError:
      resp Http400, getCurrentExceptionMsg()
    except JsonParsingError:
      resp Http400, "Invalid JSON."
    except:
      resp Http400, "Unknown JSON parsing error."

