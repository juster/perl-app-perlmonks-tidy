// PMTidy.user.js - PerlMonks Code Tidier
// Greasemonkey user script
// by [juster]
// -----------------------------------------------------------------------------
// Copyright (c) 2008 Justin Davis <jrcd83@gmail.com>
// Released under the Perl Artistic License.
// http://www.perlfoundation.org/legal/licenses/artistic-2_0.html
// -----------------------------------------------------------------------------
// Inspired by and started from Jon Allen's AJAX perl highlighter:
// Project website: http://perl.jonallen.info/projects/syntaxhighlighting
// -----------------------------------------------------------------------------
// ==UserScript==
// @name           PerlMonks Code Tidier
// @namespace      http://www.perlmonks.com/?node=juster
// @description    Highlights/reformats code blocks using AJAX and perl script.
// @include        http://www.perlmonks.com/*
// @include        http://www.perlmonks.org/*
// @include        http://perlmonks.com/*
// @include        http://perlmonks.org/*
// ==/UserScript==

// --CONFIGURATION---------------------------------------------------------
//         cgiurl   - The url of a PMTidy cgi script.
TidyConfig          = new Object();
//TidyConfig.cgiurl   = 'http://juster.info/perl/pmtidy/pmtidy-devel.pl';
TidyConfig.cgiurl   = 'http://localhost/~justin/pmtidy.pl';
// ------------------------------------------------------------------------

// This must match the cgi script's message!
const UNPERLMSG  = "How very unperlish of you!";
const PMHVersion = "1.6";

// Insert the perltidy style classes.
GM_addStyle("\
.c  { color: #228B22;} /* comment */\n\
.cm { color: #000000;} /* comma */\n\
.co { color: #000000;} /* colon */\n\
.h  { color: #CD5555; font-weight:bold;} /* here-doc-target */\n\
.hh { color: #CD5555; font-style:italic;} /* here-doc-text */\n\
.i  { color: #00688B;} /* identifier */\n\
.j  { color: #CD5555; font-weight:bold;} /* label */\n\
.k  { color: #8B008B; font-weight:bold;} /* keyword */\n\
.m  { color: #FF0000; font-weight:bold;} /* subroutine */\n\
.n  { color: #B452CD;} /* numeric */\n\
.p  { color: #000000;} /* paren */\n\
.pd { color: #228B22; font-style:italic;} /* pod-text */\n\
.pu { color: #000000;} /* punctuation */\n\
.q  { color: #CD5555;} /* quote */\n\
.s  { color: #000000;} /* structure */\n\
.sc { color: #000000;} /* semicolon */\n\
.v  { color: #B452CD;} /* v-string */\n\
.w  { color: #000000;} /* bareword */\n\
.embed-code-dl span { font-size: smaller; }\n   \
");

// <font> tags throw greasemonkey (or firefox?) off in strange and exotic ways
// when it comes to manipulating the DOM.  So I'll just try to use CSS
// like someone from this decade... (the embed-code-dl stuff above)

const CODE_ORIG      = 0;
const CODE_HILITE    = 1;
const CODE_TIDY      = 2; 

/**
 * @param codeText The <tt class='codetext'> tag
 */
function TidyCode( codeText ) {
    const CODE_ERR_START  = 3;
    const CODE_ERR_SYNTAX = 3;
    const CODE_ERR_CGI    = 4;

    // codeElem should be the <p class="code"> tag element
    // private
    var self       = this;
    var dispStatus = 0;
    var codeElem   = codeText;              // <tt> tag class="codetext"
    var topElem;
    var dlElem;

    // The loop finds our elements
    for(var codeParent = codeText.parentNode ; ;
        codeParent=codeParent.parentNode) {

        var tagName = codeParent.nodeName;
        var className = codeParent.className;

        // If there is a font tag enclosing many nested tags, the font
        // tag is duplicated in the DOM to enclose every nested tag... strange?
        if(tagName == 'FONT') /*skip it*/ ;

        // Top level nodes in the Code section do not have <div>/<span> between
        // their <p>/<pre> and <tt> tags.
        else if( tagName == 'DIV' || tagName == 'SPAN' ) {
            if( className != 'codeblock' ) {
                GM_log( 'Error: Enclosing '+codeParent.nodeName+' tag is not of the '+
                        'codeblock class, as expected.' );
                return;
            }
            dlElem = codeParent.parentNode.getElementsByTagName(tagName)[1];
        }

        // This is what we are trying to reach, the outermost "code" class tag.
        else if( tagName == 'P' || tagName == 'PRE' ) {
            if( className != 'code' ) {
                GM_log( 'Error: Enclosing '+codeParent.nodeName+' tag is not of the '+
                        'code class, as expected.' );
                return;
            }
            topElem = codeParent;
            break; // END LOOP
        }

        else {
            GM_log( 'Error: Unknown '+codeParent.nodeName+' tag enclosing the '+
                    '<tt class="codetext"> code block.' );
            return;
        }
    }

    // Code can have <font size="-1"> tags inside the <tt>
    if(codeElem.getElementsByTagName('font').length > 0 ) {
        codeElem = codeElem.getElementsByTagName('font')[0];
    }
    
    if( !dlElem ) {
        dlElem = document.createElement('DIV');
        dlElem.className = 'embed-code-dl';

        //GM_log(codeElem.nodeName);
        if(codeElem.nodeName == 'FONT') {
            var fontTag = document.createElement('FONT');
            fontTag.setAttribute('size', '-1');
            fontTag.appendChild(dlElem);
            topElem.appendChild(fontTag);
        }
        else {
            topElem.appendChild(dlElem);
        }
    }

    var linkElems     = new Array;
    var origCodeHTML  = codeElem.innerHTML;
    var hiHTML        = 'Loading...';
    var tidyHTML      = 'Loading...';

    var id = TidyCodeBlocks.length;
    TidyCodeBlocks.push(this);

    request(id,
            'code=' + encodeURIComponent(origCodeHTML.replace(/%/g, '%25')) +
            ';tag=' + topElem.tagName);

    function updateLinks() {
        var ourLink;
        while ( ourLink = linkElems.pop() ) {
            dlElem.removeChild(ourLink);
        }

        if( dispStatus >= CODE_ERR_START ) {
            // If some error occurred then we display the error message
            // next to the [download] link.
            var message;
            switch( dispStatus ) {
            case CODE_ERR_SYNTAX: message = 'skipped';     break;
            case CODE_ERR_CGI:    message = 'cgi error';   break;
            default:              message = 'unknown err'; break;
            }

            var tmp;
            tmp = document.createElement('span');
            tmp.appendChild(document.createTextNode('['+message+']'));
            linkElems.push(tmp);
            dlElem.appendChild(tmp);
            return;
        }

        for ( var i=0 ; i<3 ; ++i ) {
            var name = '';
            switch(i) {
            case 0: name = 'plain';  break;
            case 1: name = 'hilite'; break;
            case 2: name = 'tidy';   break;
            }

            var link = document.createElement( dispStatus == i ? 'span' : 'a' );

            if ( dispStatus != i ) {
                var handler = new Function('event',
                                           'TidyCodeBlocks['+id+'].setDisplay('+i+');');
                link.href="javascript:void(0);";
                link.addEventListener('click', handler, true);
            }
            link.appendChild(document.createTextNode('['+name+']'));

            dlElem.appendChild(link);
            linkElems.push(link);
        }
    };

    function updateCode() {
        switch ( dispStatus ) {
        case 0: codeElem.innerHTML = origCodeHTML; break;
        case 1: codeElem.innerHTML = hiHTML;       break;
        case 2: codeElem.innerHTML = tidyHTML;     break;
        }
        return 1;
    };

    function request(ownerid, content) {
        GM_xmlhttpRequest({
                method: 'POST',
                url: TidyConfig.cgiurl,
                headers: { "User-Agent":"PerlMonksHilight/"+PMHVersion,
                           "Content-Type":"application/x-www-form-urlencoded; charset=ISO-8859-1"
                        },
                data: content,
                onload: new Function("responseDetails",
                                     'code = TidyCodeBlocks['+ownerid+']; \
                                      code.onResponse(responseDetails);')
                    });
    };

    function getTagCDATA(doc, tagName) {
        var elems = doc.getElementsByTagName(tagName);
        var elem = elems[0];
        for( var i=0; i < elem.childNodes.length; ++i ) {
            if( elem.childNodes[i].nodeType == 4 ) {
                return elem.childNodes[i].nodeValue;
            }
        }
        return;
    }

    // public
    this.onResponse = function(responseDetails) {
        if(responseDetails.status != 200) {
            dispStatus = CODE_ERR_CGI; updateLinks();
            return;
        }

        var parser = new DOMParser();
        var doc = parser.parseFromString(responseDetails.responseText,
                                         'text/xml');

        var status = doc.getElementsByTagName('status')[0].firstChild.nodeValue;
        if( status != 'success' ) {
            dispStatus = CODE_ERR_SYNTAX; updateLinks();
            return;
        }

        hiHTML   = getTagCDATA(doc, 'hilitecode');
        tidyHTML = getTagCDATA(doc, 'tidycode');

        updateLinks();
    };

    this.setDisplay = function( displayCode ) {
        //GM_log('setStatus called with arg='+status);
        if( dispStatus >= CODE_ERR_START ) return;
        dispStatus = displayCode;
        updateCode();
        updateLinks();
    };
}

var TidyCodeBlocks = new Array;

// Codemonkey menu commands

function batchSetDisplay( newStatus )
{
    for( var i=0; i<TidyCodeBlocks.length; ++i ) {
        TidyCodeBlocks[i].setDisplay(newStatus);
    }   
}

function menuRevertAll()    { batchSetDisplay(CODE_ORIG); }
function menuHighlightAll() { batchSetDisplay(CODE_HILITE); }
function menuTidyAll()      { batchSetDisplay(CODE_TIDY); }

function PerlMonksHighlight() {
    var ttTags = document.getElementsByTagName('tt');
    var codeTexts = new Array;
    for( var i=ttTags.length-1 ; i>=0 ; --i ) {
        if(ttTags[i].className == 'codetext') {
            codeTexts.push( ttTags[i] );
        }
    }

    if(codeTexts.length == 0) {
        //GM_log('Could not find any <tt class="codetext">...</tt> tags to tidy');
        return;
    }

    for( var i = 0; i < codeTexts.length; i++ ) {
        new TidyCode(codeTexts[i]);
    }
};

GM_registerMenuCommand( 'Revert all code', menuRevertAll );
GM_registerMenuCommand( 'Highlight all code', menuHighlightAll );
GM_registerMenuCommand( 'Tidy all code', menuTidyAll );

PerlMonksHighlight();
