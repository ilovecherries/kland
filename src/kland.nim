# This is just an example to get you started. A typical binary package
# uses this file as the main entry point of the application.

import jester

import system

import norm/[sqlite]
import options
import strutils
import model
import nimcrypto

from base64 import encode
from re import re
from times import now, format

import html

let dbConn* = open(":memory", "", "", "")
dbConn.createTables(newPost())
dbConn.createTables(newThread())


proc getThread(threadId: int64): Option[Thread] =
  var thread = newThread()
  try:
    dbConn.select(thread, "Thread.id = ?", threadId)
    return some(thread)
  except NotFoundError:
    return none(Thread)


proc generateTrip(trip: string): string =
  let hash = sha512.digest(trip)
  encode(hash.data)[0..9]


# TODO: i need to find out what type the form data is and extract the
# post creation into a separate function...
proc postFromFormData(data: MultiData, threadId: int64): Post =
  if not (("content" in data) and data["content"].body.len() != 0):
    raise newException(ValueError, "Content is missing from post")

  let content = data["content"].body
  let author = if ("author" in data) and data["author"].body.len() != 0:
    some(data["author"].body)
    else: none(string)
  let trip = if ("trip" in data) and data["trip"].body.len() != 0:
    some(generateTrip(data["trip"].body))
    else: none(string)
  let filename = if ("image" in data) and data["image"].body.len() != 0:
    let n = "/bucket/" & $(now().format("yyyyMMddhhmmssffffff"))
    writeFile("public" & n, data.getOrDefault("image").body)
    some(n)
    else: none(string)

  return newPost(content, threadId, author = author, trip = trip,
    image = filename)


routes:
  get "/":
    var response = ""
    response &= generateHeader("20% ruined", false)
    response &= generatePostFieldHTML()
    response &= generateThreadEntriesHTML(dbConn)
    resp generateDocumentHTML("welcome to kland!", response)


  get "/threads/":
    redirect "/"


  get re"^\/threads/([0-9]+)$":
    let id = parseInt(request.matches[0])
    var response = ""
    var title = ""
    # check if thread exists
    block:
      var thread = newThread()
      try:
        dbConn.select(thread, "Thread.id = ?", id)
        response &= generateHeader(thread.title, true)
        title = thread.title
      except NotFoundError:
        resp Http404, generateHeader("Thread does not exist.", true)
    block:
      var posts = @[newPost()]
      dbConn.select(posts, "Post.threadId = ?", id)
      response &= generatePostsHTML(posts)
    response &= generatePostFieldHTML(some(cast[int64](id)))
    resp generateDocumentHTML(title, response)


  # create new thread
  post "/threads/":
    let data = request.formData

    cond ("content" in data) and data["content"].body.len() != 0
    cond ("title" in data) and data["title"].body.len() != 0

    let title = data["title"].body # the title of the thread

    # clean the html content so that we don't get fucked

    var thread = newThread(title)
    dbConn.insert thread

    let threadId = dbConn.count(Thread)
    try:
      var post = postFromFormData(data, threadId)
      dbConn.insert post
    except ValueError:
      resp Http400, generateDocumentHTML(
        "Bad Request",
        generateHeader(getCurrentExceptionMsg(), true)
      )

    redirect "/threads/" & $threadId


  # create new post in thread
  post re"^\/threads/([0-9]+)$":
    let threadId = cast[int64](parseInt(request.matches[0]))
    var thread = getThread(threadId)
    if thread.isNone:
      resp Http404, generateHeader("Thread does not exist.", true)
    let data = request.formData
    try:
      var post = postFromFormData(data, threadId)
      dbConn.insert post
    except ValueError:
      resp Http400, generateDocumentHTML(
        "Bad Request",
        generateHeader(getCurrentExceptionMsg(), true)
      )

    redirect "/threads/" & $threadId
