/* -*- c -*- */
/*    gzip.xs
 *
 *    Copyright (C) 2001, Nicholas Clark
 *
 *    You may distribute this work under the terms of either the GNU General
 *    Public License or the Artistic License, as specified in perl's README
 *    file.
 *
 */
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <zlib.h>
#include <perliol.h>

/* auto|gzip|none
   lazy
   csum
   name=
   extra=
   comment=
*/
/* stick a buffer on layer below
   turn of crlf
   zalloc in the zs struct being non-NULL is sign that we need to tidy up
*/

#define GZIP_HEADERSIZE		10
#define GZIP_TEXTFLAG		0x01
#define GZIP_HAS_HEADERCRC	0x02
#define GZIP_HAS_EXTRAFIELD	0x04
#define GZIP_HAS_ORIGNAME	0x08
#define GZIP_HAS_COMMENT	0x10
/* 0x20 is encrypted, which we'll treat as if its unknown.  */
#define GZIP_KNOWNFLAGS		0x1F

#define LAYERGZIP_STATUS_NORMAL		0
#define LAYERGZIP_STATUS_INPUT_EOF	1
#define LAYERGZIP_STATUS_ZSTREAM_END	2
#define LAYERGZIP_STATUS_CONFUSED	3
#define LAYERGZIP_STATUS_1STCHECKHEADER	4

#define LAYERGZIP_FLAG_GZIPHEADER	0x00
#define LAYERGZIP_FLAG_NOGZIPHEADER	0x01 /* No gzip file header */
#define LAYERGZIP_FLAG_MAYBEGZIPHEADER	0x02 /* Look for magic number */
#define LAYERGZIP_FLAG_AUTOPOP		0x03
#define LAYERGZIP_FLAG_READMODEMASK	0x03

#define LAYERGZIP_FLAG_LAZY		0x04 /* defer header check */
#define LAYERGZIP_FLAG_OURBUFFERBELOW	0x08 /* We own the buffer below us */
#define LAYERGZIP_FLAG_DEFL_INIT_DONE	0x10 /* We own the buffer below us */

#define LAYERGZIP_GZIPHEADER_GOOD	0
#define LAYERGZIP_GZIPHEADER_ERROR	1
#define LAYERGZIP_GZIPHEADER_BADMAGIC	2
#define LAYERGZIP_GZIPHEADER_BADMETHOD	3
#define LAYERGZIP_GZIPHEADER_NOTGZIP	4    /* BEWARE. If you get this your
						buf pointer is now invald  */

#define ZIP_DEFLATED		8

typedef struct {
  PerlIOBuf	base;
  z_stream	zs;		/* zlib's struct.  */
  int		status;		/* state of the inflater */
  int		flags;		/* bitmap */
} PerlIOGzip;

/* Logic of the header passer:
   buffer is where we're reading from. It may point into the fast_gets buffer
   of the layer below, or into our private SV.
   We start, if possible in the fast_gets buffer. When we exhaust it (or if
   we can't use it) we allocate a private SV and store everything that we've
   read into it. */

static SSize_t
get_more (PerlIO *below, SSize_t wanted, SV **sv, unsigned char **buffer) {
  dTHX;       /* fetch context */
  SSize_t get, done, read;
  unsigned char *read_here;

#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip get_more f=%p wanted=%08"UVxf" sv=%p buffer=%p\n",
	       below, wanted, *sv, *buffer);
#endif

  if (!*sv) {
    /* We know there were not enough bytes available in the layer below's buffer
       We know that we started at the beginning of it, so we can calculate
       how many bytes we've passed over (but not consumed, as we didn't
       alter the pointer and count).  */
    done = *buffer - (unsigned char*) PerlIO_get_ptr(below);
    get = done + wanted; /* Need to read the lot into our SV.   */
    *sv = newSVpvn("", 0);
    if (!*sv)
      return -1;
    read_here = *buffer = SvGROW(*sv, get);
  } else {
    done = SvCUR(*sv);
    *buffer = SvGROW(*sv, done + wanted);
    get = wanted; /* Only need to read the next section  */
    read_here = *buffer + done;
  }

#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip get_more sv=%p buffer=%p done=%08"UVxf" read_here=%p get=%08"UVxf" \n", *sv, *buffer, done, read_here, get);
#endif

  read = PerlIO_read (below, read_here, wanted);
#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip get_more read=%08"UVxf"\n", read);
#endif
  if (read == -1) {
    /* Read error. Messy. Don't know what state our buffer is, and whether we
       should unread it.  Probably not.  */
    SvREFCNT_dec(*sv);
    *sv = NULL;
    return read;
  }
  if (read_here == *buffer) {
    /* We were reading into the whole buffer.  */
    SvCUR_set(*sv, read);
    return read - done;
  }
  /* We were appending.  */
  SvCUR(*sv) += read;
  return read;
}


static SSize_t
eat_nul (PerlIO *below, SV **sv, unsigned char **buffer) {
  dTHX;       /* fetch context */
  SSize_t munch_size = 256; /* Pick a size to read in. Should this double
			       each loop?  */

#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip eat_nul f=%p sv=%p buffer=%p\n",
		 below, *sv, *buffer);
#endif

  if (!*sv) {
    /* Buffer below supposed fast_gets.  */
    STDCHAR *end = PerlIO_get_base(below) + PerlIO_get_bufsiz(below);
    STDCHAR *here = (STDCHAR *)*buffer;

#if DEBUG_LAYERGZIP
    PerlIO_debug("PerlIOGzip eat_nul here=%p end=%p\n", here, end);
#endif

    while (here < end) {
      if (*here++)
	continue;

      *buffer = here;
#if DEBUG_LAYERGZIP
      PerlIO_debug("PerlIOGzip eat_nul found it! here=%p end=%p\n", here, end);
#endif
      return end-here;
    }

    *buffer = here;
#if DEBUG_LAYERGZIP
    PerlIO_debug("PerlIOGzip eat_nul no joy here=%p end=%p\n", here, end);
#endif
  }

#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip eat_nul about to loop\n");
#endif

  while (1) {
    STDCHAR *end, *here;
    SSize_t avail = get_more (below, munch_size, sv, buffer);
#if DEBUG_LAYERGZIP
    PerlIO_debug("PerlIOGzip eat_nul sv=%p buffer=%p wanted=%08"UVxf" avail=%08"UVxf"\n",
		 *sv, *buffer, munch_size, avail);
#endif
    if (avail == -1 || avail == 0)
      return -1;

    end = (STDCHAR *)SvEND(*sv);
    here = (STDCHAR *)*buffer;

#if DEBUG_LAYERGZIP
    PerlIO_debug("PerlIOGzip eat_nul here=%p end=%p\n", here, end);
#endif

    while (here < end) {
      if (*here++)
	continue;
      
      *buffer = here;
#if DEBUG_LAYERGZIP
      PerlIO_debug("PerlIOGzip eat_nul found it! here=%p end=%p\n", here, end);
#endif
      return end-here;
    }
    /* as *sv is not NULL, get_more doesn't use the input value of *buffer,
       so don't waste time setting it.  We've eaten the whole SV - that's
       all get_more cares about.  So loop and munch some more.  */
  }
}

/* gzip header is
   Magic number		0,1
   Compression type	  2
   Flags		  3
   Time			4-7
   XFlags		  8
   OS Code		  9
   */

static int
check_gzip_header (PerlIO *f) {
  dTHX;       /* fetch context */
  PerlIOGzip *g = PerlIOSelf(f,PerlIOGzip);
  PerlIO *below = PerlIONext(f);
  int code = LAYERGZIP_GZIPHEADER_GOOD;
  SSize_t avail;
  SV *temp = NULL;
  unsigned char *header;
  
#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip check_gzip_header f=%p below=%p fast_gets=%d\n",
	       f, below, PerlIO_fast_gets(below));
#endif

  if (PerlIO_fast_gets(below)) {
    avail = PerlIO_get_cnt(below);
    if (avail <= 0) {
      avail = PerlIO_fill(below);
      if (avail == 0)
	avail = PerlIO_get_cnt(below);
      else
	avail = 0;
    }
  } else
    avail = 0;

#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip check_gzip_header avail=%08"UVxf"\n", avail);
#endif

  if (avail >= GZIP_HEADERSIZE)
     header = PerlIO_get_ptr(below);
  else {
    temp = newSVpvn("", 0);
    if (!temp)
      return LAYERGZIP_GZIPHEADER_ERROR;
    header = SvGROW(temp, GZIP_HEADERSIZE);
    avail = PerlIO_read(below,header,GZIP_HEADERSIZE);
#if DEBUG_LAYERGZIP
    PerlIO_debug("PerlIOGzip check_gzip_header read=%08"UVxf"\n", avail);
#endif
    if (avail < 0)
      code = LAYERGZIP_GZIPHEADER_ERROR;
    else if (avail < 2 )
      code = LAYERGZIP_GZIPHEADER_BADMAGIC;
    else if (avail < GZIP_HEADERSIZE) {
      /* Too short, but if magic number isn't there, it's not a gzip file  */
      if (header[0] == 0x1f && header[1] == 0x8b) {
	/* It's trying to be a gzip file.  */
	code = LAYERGZIP_GZIPHEADER_ERROR;
      } else
	code = LAYERGZIP_GZIPHEADER_BADMAGIC;
    }

    if (code != LAYERGZIP_GZIPHEADER_GOOD) {
      if (avail > 0)
	PerlIO_unread (below, header, avail);
      SvREFCNT_dec(temp);
      return code;
    }
  }

#if DEBUG_LAYERGZIP
    PerlIO_debug("PerlIOGzip check_gzip_header header=%p\n", header);
#endif

  avail -= GZIP_HEADERSIZE;
  if (header[0] != 0x1f || header[1] != 0x8b)
    code = LAYERGZIP_GZIPHEADER_BADMAGIC;
  else if (header[2] != ZIP_DEFLATED)
    code = LAYERGZIP_GZIPHEADER_BADMETHOD;
  else if (header[3] & !GZIP_KNOWNFLAGS)
    code = LAYERGZIP_GZIPHEADER_ERROR;
  else { /* Check the header, and skip any extra fields */
    int flags = header[3];

#if DEBUG_LAYERGZIP
    PerlIO_debug("PerlIOGzip check_gzip_header flags=%02X\n", flags);
#endif

    header += GZIP_HEADERSIZE;
    if (flags & GZIP_HAS_EXTRAFIELD) {
      Size_t len;

      if (avail < 2) {
	/* Need some more */
	avail = get_more (below, 2, &temp, &header);
	if (avail < 2) {
	  code = LAYERGZIP_GZIPHEADER_ERROR;
	  goto bad;
	}
      }

      /* 2 byte little endian quantity, which we now know is in the buffer.  */
      len = header[0] | (header[1] << 8);
      header += 2;
      avail -= 2;

#if DEBUG_LAYERGZIP
      PerlIO_debug("PerlIOGzip check_gzip_header header=%p avail=%08"UVxf" extra len=%d\n", header, avail, (int)len);
#endif

      if (avail < len) {
	/* Need some more */
	avail = get_more (below, len, &temp, &header);
	if (avail < len) {
	  code = LAYERGZIP_GZIPHEADER_ERROR;
	  goto bad;
	}
      }
      header += len;
      avail -= len;
    }

    if (flags & GZIP_HAS_ORIGNAME) {
#if DEBUG_LAYERGZIP
      PerlIO_debug("PerlIOGzip check_gzip_header header=%p avail=%08"UVxf" has origname\n", header, avail);
#endif

      avail = eat_nul (below, &temp, &header);
      if (avail < 0) {
	code = LAYERGZIP_GZIPHEADER_ERROR;
	goto bad;
      }
    }
    if (flags & GZIP_HAS_COMMENT) {
#if DEBUG_LAYERGZIP
      PerlIO_debug("PerlIOGzip check_gzip_header header=%p avail=%08"UVxf" has comment\n", header, avail);
#endif

      avail = eat_nul (below, &temp, &header);
      if (avail < 0) {
	code = LAYERGZIP_GZIPHEADER_ERROR;
	goto bad;
      }
    }
  
    if (flags & GZIP_HAS_HEADERCRC) {
#if DEBUG_LAYERGZIP
      PerlIO_debug("PerlIOGzip check_gzip_header header=%p avail=%08"UVxf" has header CRC\n", header, avail);
#endif
      if (avail < 2) {
	/* Need some more */
	avail = get_more (below, 2, &temp, &header);
	if (avail < 2) {
	  code = LAYERGZIP_GZIPHEADER_ERROR;
	  goto bad;
	}
      }
      header += 2;
      avail -= 2;
    }
  }

  if (code == LAYERGZIP_GZIPHEADER_GOOD) {
    /* Adjust the pointer here. or free the SV */
    if (temp) {
      SSize_t unread;
#if DEBUG_LAYERGZIP
      PerlIO_debug("PerlIOGzip check_gzip_header finished. unreading header=%p avail=%08"UVxf"\n", header, avail);
#endif
      if (avail) {
	unread = PerlIO_unread (below, header, avail);
	if (unread != avail) {
#if DEBUG_LAYERGZIP
	  PerlIO_debug("PerlIOGzip check_gzip_header finished. only unread %08"UVxf"\n", unread);
#endif
	  code = LAYERGZIP_GZIPHEADER_ERROR;
	}
      }
      SvREFCNT_dec(temp);
    } else {
      PerlIO_debug("PerlIOGzip check_gzip_header finished. setting ptrcnt header=%p avail=%08"UVxf"\n", header, avail);
      PerlIO_set_ptrcnt(below,header,avail);
    }
  } else {
    /* Unread the whole the SV.  Maybe I should try to seek first. */
  bad:
    if (temp) {
      STRLEN len;
      STDCHAR *ptr = SvPV(temp, len);
#if DEBUG_LAYERGZIP
      PerlIO_debug("PerlIOGzip check_gzip_header failed. unreading ptr=%p len=%08"UVxf"\n", ptr, len);
#endif
      PerlIO_unread (below, ptr, len);
      SvREFCNT_dec(temp);
    }
    PerlIOBase(f)->flags |= PERLIO_F_ERROR;
  }
  return code;
}

static int
check_gzip_header_and_init (PerlIO *f) {
  dTHX;       /* fetch context */
  PerlIOGzip *g = PerlIOSelf(f,PerlIOGzip);
  int code;
  z_stream *z = &g->zs;
  PerlIO *below = PerlIONext(f);

#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip check_gzip_header_and_init f=%p below=%p flags=%02X\n",
	       f, below, g->flags);
#endif

  if ((g->flags & LAYERGZIP_FLAG_READMODEMASK) != LAYERGZIP_FLAG_NOGZIPHEADER) {
    code = check_gzip_header (f);
    if (code != LAYERGZIP_GZIPHEADER_GOOD) {
#if DEBUG_LAYERGZIP
      PerlIO_debug("PerlIOGzip check_gzip_header_and_init code=%d\n", code);
#endif
      if (code != LAYERGZIP_GZIPHEADER_BADMAGIC)
	return code;
      else {
	int mode = g->flags & LAYERGZIP_FLAG_READMODEMASK;
	if (mode == LAYERGZIP_FLAG_MAYBEGZIPHEADER) {
	  /* There wasn't a magic number.  But flags say that's OK.  */
	} else if (mode == LAYERGZIP_FLAG_AUTOPOP) {
	  /* There wasn't a magic number.  Muahahaha. Treat it as a normal
	     file by popping ourself.  */
	  return LAYERGZIP_GZIPHEADER_NOTGZIP;
	} else {
	  return code;
	}
      }
    }
  }
  g->status = LAYERGZIP_STATUS_NORMAL;

  /* (any header validated) */
  if (PerlIOBase(below)->flags & PERLIO_F_FASTGETS) {
#if DEBUG_LAYERGZIP
    PerlIO_debug("check_gzip_header_and_init Good. f=%p %s fl=%08"UVxf"\n",
		 below,PerlIOBase(below)->tab->name, PerlIOBase(below)->flags);
#endif
  } else {
    /* Bah. Layer below us doesn't suport FASTGETS. So we need to add a layer
       to provide our input buffer.  */
#if DEBUG_LAYERGZIP
    PerlIO_debug("check_gzip_header_and_init Bad . f=%p %s fl=%08"UVxf"\n",
		 below,PerlIOBase(below)->tab->name, PerlIOBase(below)->flags);
#endif
    if (!PerlIO_push(below,&PerlIO_perlio,"r",Nullch,0))
      return LAYERGZIP_GZIPHEADER_ERROR;
    g->flags |= LAYERGZIP_FLAG_OURBUFFERBELOW;
    below = PerlIONext(f);
  }
  assert (PerlIO_fast_gets(below));

  z->next_in = (Bytef *) PerlIO_get_base(below);
  z->avail_in = z->avail_out = 0;
  z->zalloc = (alloc_func) 0;
  z->zfree = (free_func) 0;
  z->opaque = 0;

  /* zlib docs say that next_out and avail_out are unchanged by init.
     Implication is that they don't yet need to be initialised.  */

  if (inflateInit2(z, -MAX_WBITS) != Z_OK) {
#if DEBUG_LAYERGZIP
    PerlIO_debug("check_gzip_header_and_init failed to inflateInit2");
#endif
    if (g->flags & LAYERGZIP_FLAG_OURBUFFERBELOW) {
      g->flags & ~LAYERGZIP_FLAG_OURBUFFERBELOW;
      PerlIO_pop(below);
    }
    return LAYERGZIP_GZIPHEADER_ERROR;
  }

  g->flags |= LAYERGZIP_FLAG_DEFL_INIT_DONE;

  return LAYERGZIP_GZIPHEADER_GOOD;
}


static IV
PerlIOGzip_pushed(PerlIO *f, const char *mode, const char *arg, STRLEN len)
{
  dTHX;       /* fetch context */
  PerlIOGzip *g = PerlIOSelf(f,PerlIOGzip);
  IV code = 0;
  
#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip_pushed f=%p %s %s fl=%08"UVxf" g=%p\n",
	       f,PerlIOBase(f)->tab->name,(mode) ? mode : "(Null)",
	       PerlIOBase(f)->flags, g);
  if (arg)
    PerlIO_debug("  len=%d arg=%.*s\n", (int)len, (int)len, arg);
#endif

  code = PerlIOBuf_pushed(f,mode,arg,len);
  if (code)
    return code;

  g->flags = LAYERGZIP_FLAG_GZIPHEADER;
  g->status = LAYERGZIP_STATUS_1STCHECKHEADER;

  if (len) {
    const char *end = arg + len;
    while (1) {
      int arg_bad = 0;
      const char *comma = memchr (arg, ',', len);
      STRLEN this_len = comma ? (comma - arg) : (end - arg);

#if DEBUG_LAYERGZIP
      PerlIO_debug("  processing len=%d arg=%.*s\n",
		   (int)this_len, (int)this_len, arg);
#endif

      if (this_len == 4) {
	if (memEQ (arg, "none", 4)) {
	  g->flags &= ~LAYERGZIP_FLAG_READMODEMASK;
	  g->flags |= LAYERGZIP_FLAG_NOGZIPHEADER;
	} else if (memEQ (arg, "auto", 4)) {
	  g->flags &= ~LAYERGZIP_FLAG_READMODEMASK;
	  g->flags |= LAYERGZIP_FLAG_MAYBEGZIPHEADER;
	} 	else if (memEQ (arg, "lazy", 4))
	  g->flags |= LAYERGZIP_FLAG_LAZY;
	else if (memEQ (arg, "gzip", 4)) {
	  g->flags &= ~LAYERGZIP_FLAG_READMODEMASK;
	  g->flags |= LAYERGZIP_FLAG_GZIPHEADER;
	} else
	  arg_bad = 1;
      } else if (this_len == 7) {
	if (memEQ (arg, "autopop", 7)) {
	  g->flags &= ~LAYERGZIP_FLAG_READMODEMASK;
	  g->flags |= LAYERGZIP_FLAG_AUTOPOP;
	} else
	  arg_bad = 1;
      }

      if (arg_bad)
	Perl_warn(aTHX_ "perlio: layer :gzip, unregonised argument \"%.*s\"",
		  (int)this_len, arg);

      if (!comma)
	break;
      arg = comma + 1;
    }
  }
  

  if (PerlIOBase(f)->flags & PERLIO_F_CANWRITE) {
#if DEBUG_LAYERGZIP
    PerlIO_debug("PerlIOGzip_pushed f=%p fl=%08"UVxf" including write (%X)\n",
		 f, PerlIOBase(f)->flags, PERLIO_F_CANWRITE);
#endif
    /* autopop trumps writing.  */
    if ((g->flags & LAYERGZIP_FLAG_READMODEMASK) == LAYERGZIP_FLAG_AUTOPOP) {
	PerlIO_pop(f);
	return 0;
      }
    return -1;
  }

    /* autopop trumps lazy. (basically, it's going to confuse upstream far too
     much if on the first read we pop our buffered layer off to reveal an
     unbuffered layer below us)  */
  if (!(g->flags & LAYERGZIP_FLAG_LAZY)
      || ((g->flags & LAYERGZIP_FLAG_READMODEMASK) == LAYERGZIP_FLAG_AUTOPOP)) {
    code = check_gzip_header_and_init (f);
    if (code != LAYERGZIP_GZIPHEADER_GOOD) {
      if (code == LAYERGZIP_GZIPHEADER_NOTGZIP) {
	PerlIO_pop(f);
	return 0;
      }
      return -1;
    }
  }
#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip_pushed f=%p g->status=%d g->flags=%02X\n",
	       f, g->status, g->flags);
#endif
  return 0;
}

static IV
PerlIOGzip_popped(PerlIO *f)
{
  dTHX;       /* fetch context */
  PerlIOGzip *g = PerlIOSelf(f,PerlIOGzip);
  IV code = 0;

#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip_popped f=%p %s\n",
	       f,PerlIOBase(f)->tab->name);
#endif

  if (g->flags & LAYERGZIP_FLAG_DEFL_INIT_DONE) {
    g->flags &= ~LAYERGZIP_FLAG_DEFL_INIT_DONE;
    code = inflateEnd (&(g->zs)) == Z_OK ? 0 : -1;
  }
  if (g->flags & LAYERGZIP_FLAG_OURBUFFERBELOW) {
    PerlIO *below = PerlIONext(f);
    assert (below); /* This must be a layer, or our flags a screwed, or someone
		       else has been screwing with our buffer.  */
    PerlIO_pop(below);
    g->flags &= ~LAYERGZIP_FLAG_OURBUFFERBELOW;
  }

#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip_popped f=%p %s %d\n",
	       f,PerlIOBase(f)->tab->name, (int)code);
#endif

  return code;
}

static IV
PerlIOGzip_close(PerlIO *f)
{
  dTHX;
  IV code = 0;
  PerlIOGzip *g = PerlIOSelf(f,PerlIOGzip);

#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip_close f=%p %s za=%p\n",
	       f,PerlIOBase(f)->tab->name, g->zs.zalloc);
#endif

  if (g->flags & (LAYERGZIP_FLAG_DEFL_INIT_DONE
		  | LAYERGZIP_FLAG_OURBUFFERBELOW))
    code = PerlIOGzip_popped(f);

#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip_close f=%p %d\n", f, (int)code);
#endif

  code |= PerlIOBuf_close(f);	/* Call it whatever.  */
  return code ? -1 : 0;		/* Only returns 0 if both succeeded */
}

static IV
PerlIOGzip_fill(PerlIO *f)
{
  dTHX;       /* fetch context */
  PerlIOGzip *g = PerlIOSelf(f,PerlIOGzip);
  PerlIOBuf *b = PerlIOSelf(f,PerlIOBuf);
  PerlIO *n = PerlIONext(f);
  SSize_t avail;
  int status = Z_OK;

#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip_fill f=%p g->status=%d\n", f, g->status);
#endif

  if (g->status == LAYERGZIP_STATUS_CONFUSED || g->status == LAYERGZIP_STATUS_ZSTREAM_END)
    return -1;	/* Error state, or EOF has been seen.  */

  if (g->status == LAYERGZIP_STATUS_1STCHECKHEADER) {
    if (check_gzip_header_and_init (f) != LAYERGZIP_GZIPHEADER_GOOD) {
      g->status == LAYERGZIP_STATUS_CONFUSED;
      PerlIOBase(f)->flags |= PERLIO_F_ERROR;
      return -1;
    }
  }

  if (!b->buf)
    PerlIO_get_base(f); /* allocate via vtable */

  b->ptr = b->end = b->buf;
  g->zs.next_out = (Bytef *) b->buf;
  g->zs.avail_out = b->bufsiz;

#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip_fill next_out=%p avail_out=%08"UVxf"\n",
	       g->zs.next_out,g->zs.avail_out);
#endif

  assert (PerlIO_fast_gets(n));
  /* loop while we see no output.  */
  while (g->zs.next_out == (Bytef *) b->buf) {
    /* If we have run out of input then read some more.  */
    avail = PerlIO_get_cnt(n);
#if DEBUG_LAYERGZIP
    PerlIO_debug("PerlIOGzip_fill avail=%08"UVxf"\n",avail);
#endif
    if (avail <= 0) {
      avail = PerlIO_fill(n);
      if (avail == 0) {
	avail = PerlIO_get_cnt(n);
#if DEBUG_LAYERGZIP
	PerlIO_debug("PerlIOGzip_fill refill, avail=%08"UVxf"\n",avail);
#endif
      } else {
	/* To make this non blocking friendly would we need to change this?  */
	if (PerlIO_error(n)) {
	  /* I'm assuming that the error on the input stream is persistent,
	     and that as there is going to be output space, I'll get
	     Z_BUF_ERROR if no progress is possible because I've used all
	     the input I got before the error.  */
	  avail = 0;
#if DEBUG_LAYERGZIP
	PerlIO_debug("PerlIOGzip_fill error, avail=%08"UVxf"\n",avail);
#endif
	} else if (PerlIO_eof(n)) {
	  g->status = LAYERGZIP_STATUS_INPUT_EOF;
	  avail = 0;
#if DEBUG_LAYERGZIP
	PerlIO_debug("PerlIOGzip_fill input eof, avail=%08"UVxf"\n",avail);
#endif
	} else {
	  avail = 0;
#if DEBUG_LAYERGZIP
	  PerlIO_debug("PerlIOGzip_fill how did I get here?, avail=%08"UVxf"\n",avail);
#endif
	}
      }
    }


    g->zs.avail_in = avail;
    g->zs.next_in = (Bytef *) PerlIO_get_ptr(n);
    /* Z_SYNC_FLUSH to get as much output as possible if there's no input left.
       This may be pointless, but I'm hoping that this is enough to make non-
       blocking work by forcing as much output as possible if the input blocked.
    */
#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip_fill preinf  next_in=%p avail_in=%08"UVxf"\n",
	       g->zs.next_in,g->zs.avail_in);
#endif
    status = inflate (&(g->zs), avail ? Z_NO_FLUSH : Z_SYNC_FLUSH);
#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip_fill postinf next_in=%p avail_in=%08"UVxf" status=%d\n",
	       g->zs.next_in,g->zs.avail_in, status);
#endif
    /* And we trust that zlib gets these two correct  */
    PerlIO_set_ptrcnt(n,g->zs.next_in,g->zs.avail_in);

    if (status != Z_OK) {
      if (status == Z_STREAM_END) {
	g->status = LAYERGZIP_STATUS_ZSTREAM_END;
	PerlIOBase(f)->flags |= PERLIO_F_EOF;
      } else {
	PerlIOBase(f)->flags |= PERLIO_F_ERROR;
      }
      break;
    }

  }  /* loop until we read enough data.
	hopefully not literally forever. Z_BUF_ERROR should be generated if
	there is a buffer problem.  Z_OK will only appear if there is progress -
	ie either input is consumed (it must be available for this) or output is
	generated (there must be space for this).  Hence not consuming any input
	whilst also not generating any more output is an error we will spot and
	barf on.  */

#if DEBUG_LAYERGZIP
  PerlIO_debug("PerlIOGzip_fill leaving next_out=%p avail_out=%08"UVxf"\n",
	       g->zs.next_out,g->zs.avail_out);
#endif
  
  if (g->zs.next_out != (Bytef *) b->buf) {
    /* Success if we got at least one byte. :-) */
    b->end = g->zs.next_out;
    PerlIOBase(f)->flags |= PERLIO_F_RDBUF;
    return 0;
  }
  return -1;
}


/* Hmm. These need to be public  */
static SSize_t
PerlIO_write_fail(PerlIO *f, const void *vbuf, Size_t count)
{
  return -1;
}

static IV
PerlIO_seek_fail(PerlIO *f, Off_t offset, int whence)
{
  return -1;
}


PerlIO_funcs PerlIO_gzip = {
  "gzip",
  sizeof(PerlIOGzip),
  PERLIO_K_BUFFERED,
  PerlIOBase_fileno,
  PerlIOBuf_fdopen,	/* Do these   */
  PerlIOBuf_open,	/* three work */
  PerlIOBuf_reopen,	/* like this? */
  PerlIOGzip_pushed,
  PerlIOGzip_popped,
  PerlIOBuf_read,
  PerlIOBuf_unread, /* I am not convinced that this is going to work */
  PerlIO_write_fail,	/* PerlIOBuf_write, */
  PerlIO_seek_fail,	/* PerlIOBuf_seek, */
  PerlIOBuf_tell,
  PerlIOGzip_close,
  PerlIOBase_noop_ok,	/* PerlIOBuf_flush, Hmm. open() expects to flush :-( */
  PerlIOGzip_fill,
  PerlIOBase_eof,
  PerlIOBase_error,
  PerlIOBase_clearerr,
  PerlIOBuf_setlinebuf,
  PerlIOBuf_get_base,
  PerlIOBuf_bufsiz,
  PerlIOBuf_get_ptr,
  PerlIOBuf_get_cnt,
  PerlIOBuf_set_ptrcnt,
};

MODULE = PerlIO::gzip		PACKAGE = PerlIO::gzip		

BOOT:
	PerlIO_define_layer(&PerlIO_gzip);
