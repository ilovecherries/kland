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


# i assume this just makes an sqlite db in memory
let dbConn* = open(":memory", "", "", "")
dbConn.createTables(newPost())
dbConn.createTables(newThread())


var examplePost = newPost("Hello, !!!!!")
dbConn.insert examplePost

func generateHeader(msg: string): string =
  header(
    h1(msg),
  )


func generatePostHTML(post: Post): string =
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
        class = "trip"
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
      class = "references"
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
    let thread = parseInt(request.matches[0])
    var response = ""
    block:
      var posts = @[newPost()]
      dbConn.select(posts, "Post.threadId = ?", thread)
      for i in posts:
        response = response & generatePostHTML(i)
    resp response


  # create new thread
  post "/threads/":
    let data = request.formData

    cond "content" in data
    cond "title" in data

    let content = data["content"].body # content of the first post
    let title = data["title"].body # the title of the thread

    let author =
      if "author" in data: some(data["author"].body) else: none(string)

    var thread = newThread(title)
    dbConn.insert thread

    # it seems like inserting the element in the database doesn't update
    # the base object to have the ID, so we have to get it from here...
    block:
      var threads = @[newThread()]
      dbConn.select(threads, "Thread.id = ?", thread.id)
      for i in threads:
        var post = newPost(content, i.id, author)
        dbConn.insert post

    resp "Thread successfully created"


  # create new post in thread
  post re"^\/threads/([0-9]+)$":
    let data = request.formData

    cond "threadId" in data
    cond "content" in data

    let threadId: int64 = parseInt(data["threadId"].body)
    let content = data["content"].body
    let author =
      if "author" in data: some(data["author"].body) else: none(string)

    var post = newPost(content, threadId, author)
    dbConn.insert post

    resp "Post successfully created"

