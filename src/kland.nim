import jester
import system

import norm/[sqlite]
import options
import strutils
import model
import nimcrypto

from htmlgen import img
from base64 import encode
from re import re
from times import now, format
from sugar import collect

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


func keyExists(data: MultiData, key: string): bool =
  (key in data) and data[key].body.len() != 0


proc postFromFormData(data: MultiData, threadId: int64): Post =
  if not data.keyExists("content"):
    raise newException(ValueError, "Content is missing from post")

  let content = data["content"].body
  let author = if data.keyExists("author"):
    some(data["author"].body)
    else: none(string)
  let trip = if data.keyExists("trip"):
    some(generateTrip(data["trip"].body))
    else: none(string)
  let filename = if data.keyExists("image"):
    let n = "/bucket/" & $(now().format("yyyyMMddhhmmssffffff"))
    writeFile("public" & n, data.getOrDefault("image").body)
    some(n)
    else: none(string)

  return newPost(content, threadId, author = author, trip = trip,
    image = filename)


routes:
  get "/":
    var response = ""
    response &= generateHeader(img(src = "/sbsland.gif", alt = "sbs land"), false)
    response &= generatePostFieldHTML()
    const sqlText = """
      SELECT DISTINCT t.title, t.id
      FROM            "Thread" t
           INNER JOIN "Post" p
           ON         p.threadId = t.id
      ORDER BY        p.id DESC
    """
    let threads = collect(newSeq):
      for i in dbConn.getAllRows(sql sqlText):
        Thread(
          title: i[0].to(string),
          id: i[1].to(int64)
        )
    for i in threads:
      echo i.title
    response &= generateThreadEntriesHTML(dbConn, threads)

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

    cond data.keyExists("content")
    cond data.keyExists("title")

    let title = data["title"].body # the title of the thread

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
