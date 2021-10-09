import htmlgen
import model
import options
from times import format, DateTime
from sequtils import foldl
from strutils import replace
from xmltree import escape
import norm/[sqlite]
from re import re, replacef


func generateHeader*(msg: string, showThreads: bool): string =
  `div`(
    class = "header",
    h1(msg),
    `div`(
      class = "nav",
      if showThreads: a(href = "/", "Thread list") else: ""
    )
  )


func formatPostTime(timestamp: DateTime): string =
  timestamp.format("d/MM/yyyy, h:mm:ss tt")


func generatePostHTML*(post: Post, references: seq[int64] = @[]): string =
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
      formatPostTime(post.timestamp)
    ),
    a(
      href = "#p" & $post.id,
      class = "postlink",
      $post.id
    ),
    `div`(
      class = "references",
      foldl(
        references,
        a & a(
          class = "reference",
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
      escape(post.content).replacef(re"&gt;&gt;([0-9]+)", a(
        class = "reference",
        href = "#p$1",
        "&gt;&gt;$1"
    ))
  )
  )
  )


proc generateThreadEntryHTML*(dbConn: DbConn, thread: Thread): string =
  var pcount = dbConn.count(Post, "*", dist = false, "threadId = ?", thread.id)
  var recentPost = newPost()
  dbConn.select(recentPost, "threadId = ? ORDER BY id DESC", thread.id)
  var firstPost = newPost()
  dbConn.select(firstPost, "threadId = ?", thread.id)
  `div`(
    class = "thread",
    a(
      href = "/threads/" & $thread.id,
      thread.title
    ),
    time(
      class = "lastPost",
      formatPostTime(recentPost.timestamp)
    ),
    time(
      class = "firstPost",
      formatPostTime(firstPost.timestamp)
    ),
    span(
        class = "posts",
        "P:" & $pcount
    )
  )

proc generateThreadEntriesHTML*(dbConn: DbConn): string =
  var threads = @[newThread()]
  dbConn.selectAll(threads)
  var threadsHTML = ""
  for i in threads:
    threadsHTML = generateThreadEntryHTML(dbConn, i) & threadsHTML
  `div`(
      class = "threads",
      threadsHTML
  )


func generatePostFieldHTML*(threadId: Option[int64] = none(int64)): string =
  form(
    action = "/threads/" & (if threadId.isNone: "" else: $threadId.get()),
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
    if threadId.isNone: input(
      name = "title",
      id = "pform-title",
      maxlength = "254",
      placeholder = "Subject",
      required = ""
    )
    else: "",
    input(
      `type` = "file",
      name = "image",
      id = "pform-image",
      accept = "image/*"
    ),
    textarea(
      name = "content",
      id = "pform-content",
      placeholder = "Content",
      required = ""
    ),
    input(
      `type` = "submit",
      value = "Post"
    )
  )


proc generatePostsHTML*(posts: seq[Post]): string =
  echo escape(posts[0].content)
  `div`(
    class = "posts",
    foldl(posts, a & generatePostHTML(b), "")
  )


func generateDocumentHTML*(title: string, body: string): string =
  "<!DOCTYPE html>" & html(
    head(
      title(title),
      meta(
        name = "viewport",
        content = "width=device-width,maximum-scale=1"
    ),
    meta(charset = "UTF-8"),
    link(
      rel = "stylesheet",
      `type` = "text/css",
      href = "/style.css"
  ),
  ),
    body(
      body
    )
  )
