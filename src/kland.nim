# This is just an example to get you started. A typical binary package
# uses this file as the main entry point of the application.

import jester
from htmlgen import `div`, h1, span, time, header, a, p

import system
from times import format

import norm/[sqlite]
import options
import re
import strutils
from strformat import fmt
import model
from sequtils import foldl


# i assume this just makes an sqlite db in memory
let dbConn* = open(":memory", "", "", "")
dbConn.createTables(newPost())
dbConn.createTables(newThread())


func generateHeader(msg: string): string =
  header(
    h1(msg),
  )


iterator reverse*[T](a: seq[T]): T {.inline.} =
  var i = len(a) - 1
  while i > -1:
    yield a[i]
    dec(i)


func generatePostHTML(post: Post, references: seq[int64] = @[]): string =
  `div`(
    id = "p" & $post.id,
    class = "post",
    `div`(
      class = "postinfo",
      span(
        class = "username",
        if post.author.isNone: "Anonymous" else: post.author.get()
      ),
      span(
        class = "trip",
        if post.trip.isNone: "" else: post.trip.get()
    ),
    time(
      post.timestamp.format("d/MM/yyyy, h:mm:ss tt")
    ),
    a(
      href = "#p" & $post.id,
      class = "postlink",
      "#" & $post.id
    ),
    # oh, these are the posts that link to it... ummm... ok ill figure out how
    # to do this later lol
    `div`(
      class = "references",
      foldl(
        references,
        a & a(
          href = "#p" & $b,
          ">>" & $b
      ),
        "")
    )
  ),
  # TODO: need to add the post image
  span(
    class = "content",
    p(
      post.content
    )
  )
  )


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
    let id = parseInt(request.matches[0])
    var response = ""
    # check if thread exists
    block:
      var thread = newThread()
      try:
        dbConn.select(thread, "Thread.id = ?", id)
        response &= generateHeader(thread.title)
      except NotFoundError:
        resp Http404, generateHeader("Thread does not exist.")
    block:
      var posts = @[newPost()]
      var postsHTML = ""
      dbConn.select(posts, "Post.threadId = ?", id)
      for i in posts.reverse():
        postsHTML = generatePostHTML(i, @[cast[int64](3), cast[int64](8)]) & postsHTML
      response &= postsHTML
    resp response


  # create new thread
  post "/threads/":
    let data = request.formData

    cond "content" in data
    cond "title" in data

    let content = data["content"].body # content of the first post
    let title = data["title"].body # the title of the thread

    let author =
      if "author" in data: some(data["trip"].body) else: none(string)
    let trip =
      if "trip" in data: some(data["trip"].body) else: none(string)

    var thread = newThread(title)
    dbConn.insert thread

    # it seems like inserting the element in the database doesn't update
    # the base object to have the ID, so we have to get it from here...
    block:
      let threadId = dbConn.count(Thread)
      echo threadId
      var post = newPost(content, threadId, author = author, trip = trip)
      dbConn.insert post

    resp "Thread successfully created"


  # create new post in thread
  post re"^\/threads/([0-9]+)$":
    let threadId = cast[int64](parseInt(request.matches[0]))
    let data = request.formData

    cond "content" in data

    let content = data["content"].body
    let author =
      if "author" in data: some(data["author"].body) else: none(string)
    let trip =
      if "trip" in data: some(data["trip"].body) else: none(string)

    var post = newPost(content, threadId, author = author, trip = trip)
    dbConn.insert post

    resp "Post successfully created"

