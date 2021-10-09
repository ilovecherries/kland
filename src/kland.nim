# This is just an example to get you started. A typical binary package
# uses this file as the main entry point of the application.

import jester
from htmlgen import `div`, h1, span, time, header, a, p, img, form, input, textarea

import system
from times import format

import norm/[sqlite]
import options
import strutils
import model

from re import re
from strformat import fmt
from sequtils import foldl


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
  if post.image.isNone: "" else:
    `div`(
      class = "postimage",
      a(
        class = "directlink",
        href = post.image.get(),
        post.image.get()
      ),
      a(
        href = post.image.get(),
        img(
          src = post.image.get(),
          alt = "Post Image"
        )
      )
    ),
  span(
    class = "content",
    p(
      post.content
    )
  )
  )


func generateThreadEntryHTML(thread: Thread): string =
  `div`(
    class = "thread",
    a(
      href = "/threads/" & $thread.id,
      thread.title
    ),
    # we should figure out how to select things backwards first so this isn't so
    # inefficient
    # time(
    #   class="lastpost"
    # )
  )


func generateSendPostFieldHTML(threadId: int64): string =
  form(
    action = "/threads/" & $threadId,
    `method` = "post",
    class = "postform",
    enctype = "multipart/form-data",
    input(
      name = "author",
      id = "pform-author",
      maxlength = "30",
      placeholder = "Nickname (optional)"
    ),
    input(
      name = "trip",
      id = "pform-trip",
      maxlength = "254",
      placeholder = "Trip (optional)"
    ),
    input(
      `type` = "file",
      name = "image",
      id = "pform-image",
      accept = "image/*"
    ),
    textarea(
      name = "content",
      id = "pform-content",
      placeholder = "Content"
    ),
    input(
      `type` = "submit",
      value = "Post"
    )
  )


func generateCreateThreadFieldHTML(): string =
  form(
    action = "/threads/",
    `method` = "post",
    class = "postform",
    enctype = "multipart/form-data",
    input(
      name = "author",
      id = "pform-author",
      maxlength = "30",
      placeholder = "Nickname (optional)"
    ),
    input(
      name = "trip",
      id = "pform-trip",
      maxlength = "254",
      placeholder = "Trip (optional)"
    ),
    input(
      name = "title",
      id = "pform-title",
      maxlength = "254",
      placeholder = "Subject"
    ),
    input(
      `type` = "file",
      name = "image",
      id = "pform-image",
      accept = "image/*"
    ),
    textarea(
      name = "content",
      id = "pform-content",
      placeholder = "Content"
    ),
    input(
      `type` = "submit",
      value = "Post"
    )
  )


routes:
  get "/":
    var threads = @[newThread()]
    dbConn.selectAll(threads)
    var response = ""
    response &= generateCreateThreadFieldHTML()
    for i in threads.reverse():
      response &= generateThreadEntryHTML(i)
    resp response


  # this is just for a test
  get re"^\/post/([0-9]+)$":
    let id = parseInt(request.matches[0])
    var posts = @[newPost()]
    dbConn.select(posts, "Post.id = ?", id)
    for i in posts:
      echo i[]
    resp fmt"check console"

  get "/threads/":
    redirect "/"

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
    response &= generateSendPostFieldHTML(id)
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

    let threadId = dbConn.count(Thread)
    var post = newPost(content, threadId, author = author, trip = trip)
    dbConn.insert post

    redirect "/threads/" & $threadId


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

    redirect "/threads/" & $threadId

