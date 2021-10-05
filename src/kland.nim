# This is just an example to get you started. A typical binary package
# uses this file as the main entry point of the application.

import jester, htmlgen

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
    var post = @[newPost()]
    dbConn.select(post, "Post.id = ?", id)
    for i in post:
      echo i[]
    resp fmt"check console"
    
  get re"^\/threads/([0-9]+)$":
    let thread = parseInt(request.matches[0])
    resp fmt"This is thread {thread}"

  # i kind of forgot that this ID is supposed to be the thread number agh
  # post magically not existing...
  post re"^\/threads/([0-9]+)$":
    let threadId = parseInt(request.matches[0])
    var data: JsonNode
    try:
      data = parseJson(@"payload")
      
      if not data.hasKey("content"):
        resp Http400, "The content is missing from the payload."
      
      let content = data["content"].getStr()
      # we should sanitize the content first beforehand so that we can detect
      # garbage such as ZWSP so that it's impossible to make empty messages?
      # (OR NOT, ZWSP and making you think you're tricking the system is kind
      #  of fun lol)
      if content.len == 0:
        resp Http400, "The content is empty."

      if threadId < 1:
        resp Http400, "The thread ID must be larger than zero."
      
      # we should check if the thread exists
      var threads = @[newThread()]
      dbConn.select(post, "Thread.id = ?", threadId)
      if threads.len() == 0:
        resp Http400, fmt"The thread ID {threadId} does not exist"

      let author: Option[string] =
        if data.hasKey("author"): data["author"].getStr() else: none

      dbConn.insert newPost(content, threadId)
      
    except JsonParsingError:
      resp Http400, "Invalid JSON."
    except:
      resp Http400, "Unknown JSON parsing error."

