/* PMTidy.user.js - PerlMonks Code Tidier
 * Greasemonkey user script
 * by [juster] on PerlMonks
 *-----------------------------------------------------------------------------
 * Copyright (c) 2011 Justin Davis <jrcd83@gmail.com>
 * Released under the Perl Artistic License.
 * http://www.perlfoundation.org/legal/licenses/artistic-2_0.html
 *-----------------------------------------------------------------------------
 * Inspired by and started from Jon Allen's AJAX perl highlighter:
 * Project website: http://perl.jonallen.info/projects/syntaxhighlighting
 *-----------------------------------------------------------------------------
 */

// ==UserScript==
// @name           PerlMonks Code Tidier
// @namespace      http://www.perlmonks.com/?node=juster
// @description    Highlights/reformats code blocks using AJAX and PerlTidy.
// @include        http://www.perlmonks.com/*
// @include        http://www.perlmonks.org/*
// @include        http://perlmonks.com/*
// @include        http://perlmonks.org/*
// ==/UserScript==

const PMTIDY_AGENT   = 'PMTidy';
const PMTIDY_VERSION = '1.5';
const PMTIDY_CGI_URL = 'http://juster.info/perl/pmtidy/';

// Each code corresponds to the links under the code text and
// different formatting.

const CODE_ORIG      = 0;
const CODE_HILITE    = 1;
const CODE_TIDY      = 2;

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
            .embed-code-dl span { font-size: smaller; }\n\
            ");

function TidyCode(codeText, idNumber)
{
    // PRIVATE ///////////////////////////////////////////////////////////////
    const CODE_ERR_START  = 3;
    const CODE_ERR_SYNTAX = 3;
    const CODE_ERR_CGI    = 4;

    var self         = this;
    var dispStatus   = 0;
    var id           = idNumber;

    var linkElems    = new Array;
    var codeElem     = codeText; // <tt class="codetext"> tag
    var topElem;
    var dlElem;

    var hiHTML       = 'Loading...';
    var tidyHTML     = 'Loading...';
    var origCodeHTML;

    // Finds the dlElem (<div> surrounding the [download] link)
    // and topElem      (the <p> or <pre> tag with class="code")
    function findElements(anscestorNode)
    {
        var tagName   = anscestorNode.nodeName;
        var className = anscestorNode.className;

        switch(tagName){
        case 'FONT': break; /*skip it*/

        // Top level nodes in the Code section do not have
        // <div>/<span> between their <p>/<pre> and <tt> tags.
        case 'DIV':
        case 'SPAN':
            if(className != 'codeblock'){
                GM_log('Error: Enclosing '+tagName+' tag is '+
                        'not of the codeblock class, as expected.');
                return false;
            }
            dlElem = anscestorNode.parentNode.getElementsByTagName(tagName)[1];
            break;

        // This is what we are trying to reach, the outermost "code" class tag.
        case 'P':
        case 'PRE':
            if(className != 'code'){
                GM_log('Error: Enclosing '+tagName+' tag is '+
                        'not of the code class, as expected.');
                return false;
            }
            topElem = anscestorNode;
            return true;

        default:
            GM_log('Error: Unknown '+tagName+' tag enclosing '+
                    'the <tt class="codetext"> code block.');
            return false;
        }

        // Recurse to the parent node.
        return findElements(anscestorNode.parentNode);
    }

    // Refreshes the little text links that are below the code text.
    function updateLinks()
    {
        // Creates an event handler function
        function makeLinkHandler(codeNum){
            return function(event){ self.setDisplay(codeNum); };
        };

        var i;
        var ourLink;
        while((ourLink = linkElems.pop())){
            dlElem.removeChild(ourLink);
        }

        if(dispStatus >= CODE_ERR_START){
            // If some error occurred then we display the error message
            // next to the [download] link.

            var message;
            switch(dispStatus){
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

        var name, link;
        var linkNames = [ 'plain', 'hilite', 'tidy' ];
        for(i = 0 ; i < linkNames.length ; ++i){
            name = linkNames[i];

            link = document.createElement(dispStatus == i ? 'span' : 'a');

            if(dispStatus != i){
                link.href ="javascript:void(0);";
                link.addEventListener('click', makeLinkHandler(i), true);
            }
            link.appendChild(document.createTextNode('['+name+']'));

            dlElem.appendChild(link);
            linkElems.push(link);
        }
    }

    function updateCode(){
        switch(dispStatus){
        case 0: codeElem.innerHTML = origCodeHTML; break;
        case 1: codeElem.innerHTML = hiHTML;       break;
        case 2: codeElem.innerHTML = tidyHTML;     break;
        }
        return 1;
    }

    function request(ownerid, code, tag)
    {
        var onResponse = function(responseDetails)
        {
            function cgiError(){
                dispStatus = CODE_ERR_CGI;
            }
            function codeError(){
                dispStatus = CODE_ERR_SYNTAX;
            }
            function xmlError(){
                GM_log("Malformed XML response from perltidy.pl!");
                cgiError();
            }

            function getcdata(node){
                kids = node.childNodes;
                for(i = 0; i < kids.length; i++){
                    if(kids[i].nodeType == 4){
                        return kids[i].nodeValue;
                    }
                }
                return;
            }

            if(responseDetails.status != 200){
                cgiError();
                updateLinks();
                return;
            }

            var xml = responseDetails.responseText;
            GM_log(xml);
            var dp = new DOMParser();
            var dom = dp.parseFromString(xml, "text/xml");
            var e = dom.documentElement;
            if(e.nodeName != "tidyresp"){
                cgiError();
            }
            else if(e.firstChild.nodeName == "error"){
                // TODO: display error message in browser
                e = e.firstChild;
                GM_log("Error with syntax highlighting:\n" + e.nodeText);
                codeError();
            }else{
                var hilited = e.getElementsByTagName('hilited')[0];
                var tidied = e.getElementsByTagName('tidied')[0];

                if(!hilited || hilited.tagName != 'hilited' ||
                   !tidied || tidied.tagName != 'tidied'){
                    xmlError();
                }else{
                    hilited = getcdata(hilited);
                    tidied = getcdata(tidied);
                    if(!hilited || !tidied){
                        xmlError();
                    }else{
                        hiHTML = hilited;
                        tidyHTML = tidied;
                    }
                }
            }
            
            updateLinks();
            return;
        };

        xmlreq = "<?xml><tidyreq>"
            + "<code><![CDATA[" + code + "]]></code>"
            + "<tag>" + tag + "</tag>"
            + "</tidyreq>";

        GM_xmlhttpRequest({
            method  : 'POST',
            url     : PMTIDY_CGI_URL,
            headers : {
                'User-Agent'   : PMTIDY_AGENT + '/' + PMTIDY_VERSION,
                'Content-Type' : 'text/xml; charset=UTF-8'
            },
            data    : xmlreq,
            onload  : onResponse
        });
    }

    // PUBLIC ////////////////////////////////////////////////////////////////

    this.setDisplay = function(displayCode){
        if(dispStatus >= CODE_ERR_START){
            return;
        }
        dispStatus = displayCode;
        updateCode();
        updateLinks();
    };

    // CONSTRUCTOR ///////////////////////////////////////////////////////////

    if(!findElements(codeElem.parentNode)){
        return null;
    }

    // Code can have <font size="-1"> tags inside the <tt>, watchout...
    if(codeElem.getElementsByTagName('font').length > 0){
        codeElem = codeElem.getElementsByTagName('font')[0];
    }

    origCodeHTML = codeElem.innerHTML;

    // Create a "download" mini-link DIV tag if one doesn't exist..
    if(!dlElem){
        dlElem = document.createElement('DIV');
        dlElem.className = 'embed-code-dl';

        // Make sure the font tags matches real link div's...
        if(codeElem.nodeName == 'FONT'){
            var fontTag = document.createElement('FONT');
            fontTag.setAttribute('size', '-1');
            fontTag.appendChild(dlElem);
            topElem.appendChild(fontTag);
        }else{
            topElem.appendChild(dlElem);
        }
    }

    request(id, origCodeHTML, topElem.tagName);
    return this;
}

var TidyCodeBlocks = new Array;

// Codemonkey menu commands

function batchSetDisplay(newStatus)
{
    var i;
    for(i = 0 ; i < TidyCodeBlocks.length ; ++i){
        TidyCodeBlocks[i].setDisplay(newStatus);
    }
}

function menuRevertAll()    { batchSetDisplay(CODE_ORIG); }
function menuHighlightAll() { batchSetDisplay(CODE_HILITE); }
function menuTidyAll()      { batchSetDisplay(CODE_TIDY); }

function PerlMonksHighlight(){
    var ttTags    = document.getElementsByTagName('tt');
    var codeTexts = new Array;
    var i;

    for(i = ttTags.length-1 ; i >= 0 ; --i){
        if(ttTags[i].className == 'codetext'){
            codeTexts.push(ttTags[i]);
        }
    }

    if(codeTexts.length == 0){
        return;
    }

    for(i = 0; i < codeTexts.length; i++){
        var codeBlock = new TidyCode(codeTexts[i], i);
        TidyCodeBlocks.push(codeBlock);
    }
};

GM_registerMenuCommand('Revert all code',    menuRevertAll);
GM_registerMenuCommand('Highlight all code', menuHighlightAll);
GM_registerMenuCommand('Tidy all code',      menuTidyAll);

PerlMonksHighlight();

/*EOF*/
