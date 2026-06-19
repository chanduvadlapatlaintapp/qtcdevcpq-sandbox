/*
        datePicker by frequency decoder (http://www.frequency-decoder.com/)

        Released under a creative commons nc-sa license (http://creativecommons.org/licenses/by-nc-sa/2.5/)

        Please credit frequency decoder in any derivitive work. Thanks.

        Change log
        ----------
        07/04/06 : Add a fix for Internet Explorer when the script is used on a secure page (thanks to John).
        06/04/06 : Added keyboard accessibiliy to the day header buttons.
        20/03/06 : Changed the day header to use buttons and not links.
        14/03/06 : Added the firstDayOfWeek and dayAbbr into the language file.
                   Added functionality that enables users to click on a day header to set the first day of the week.
                   Fixed a bug that called removeEvent and not the correct datePickerController.removeEvent.
                   Removed the firstDayOfWeek option from the regExps (now defined within the language file).
                   Fixed an Opera "redraw" bug (within the demo CSS).
        08/03/06 : Fixed the dividor->divider spelling error within the regExps.
        03/03/06 : Fixed the Internet Explorer keyPress bug.
        02/03/06 : Integrated the addEvent, removeEvent and findPosition functions into the datePicker object.
        17/02/06 : Added the "detect locale" code.
        15/02/06 : Fixed the Firefox "page scroll" bug.
        04/01/06 : Removed most of the images from the CSS for Internet Explorer.
*/

var datePickerController;

(function() {

datePicker.isSupported = typeof document.createElement != "undefined" &&
        typeof document.documentElement != "undefined" &&
        typeof document.documentElement.offsetWidth == "number";

// Detect the users browser language
datePicker.languageinfo = navigator.language ? navigator.language : navigator.userLanguage;
datePicker.languageinfo = datePicker.languageinfo ? datePicker.languageinfo.toLowerCase().replace(/-[a-z]+$/, "") : 'en';

if(datePicker.languageinfo != 'en') {
        // Load the appropriate language file
        var scriptFiles = document.getElementsByTagName('head')[0].getElementsByTagName('script');
        var loc         = "";

        for(var i = 0, scriptFile; scriptFile = scriptFiles[i]; i++) {
                if(scriptFile.src && scriptFile.src.match(/fd-datepicker/)) {
                        loc = scriptFile.src.replace("fd-datepicker", "lang/" + datePicker.languageinfo);
                        break;
                }
        }

        if(loc != "") {
                var script      = document.createElement('script');
                script.type     = "text/javascript";
                script.src      = loc;
                document.getElementsByTagName('head')[0].appendChild(script);
        }
}

// Defaults for the language should the locale file not load (defaults to English)
datePicker.months = [
                "January",
                "February",
                "March",
                "April",
                "May",
                "June",
                "July",
                "August",
                "September",
                "October",
                "November",
                "December"];
datePicker.fullDay = [
                "Monday",
                "Tuesday",
                "Wednesday",
                "Thursday",
                "Friday",
                "Saturday",
                "Sunday"];
datePicker.titles = [
                "Previous month",
                "Next month",
                "Previous year",
                "Next year"];

datePicker.daysPerMonth = [31,28,31,30,31,30,31,31,30,31,30,31];

datePicker.getDaysPerMonth = function (nMonth, nYear) {
        nMonth = (nMonth + 12) % 12;
        var res = datePicker.daysPerMonth[nMonth];
        if (nMonth == 1) {
                res += nYear % 4 == 0 && !(nYear % 400 == 0) ? 1 : 0;
        }
        return res;
};
datePicker.findPosition = function( obj ) {

        var curleft = 0;
        var orig = obj;

        if (obj.offsetParent) {
                while (obj.offsetParent) {
                        curleft += obj.offsetLeft
                        obj = obj.offsetParent;
                }
        }
        else if (obj.x) curleft += obj.x;

        obj = orig;
        var curtop = 0;
        if (obj.offsetParent) {
                while (obj.offsetParent) {
                        curtop += obj.offsetTop
                        obj = obj.offsetParent;
                }
        }
        else if (obj.y) curtop += obj.y;

        return [ curleft, curtop ];
};
function datePicker(options) {

        for(opt in options) this[opt] = options[opt];

        this.date              = new Date();
        this.matrix            = [[],[],[],[],[],[],[]];
        this.yearinc           = 1;
        this.timer             = null;
        this.pause             = 1000;
        this.timerSet          = false;
        this.opacity           = 0;
        this.opacityTo         = 0;
        this.fadeTimer         = null;
        this.div;
        this.table;
        this.staticT           = 0;
        this.interval          = new Date();
        this.firstDayOfWeek    = 0;

        var o = this;

        o.setOpacity = function(op) {
                o.div.style.opacity =  + op/100;
                o.div.style.filter = 'alpha(opacity=' + op + ')';
                o.opacity = op;
        };
        o.fade = function() {
                window.clearTimeout(o.fadeTimer);
                var diff = Math.round(o.opacity + ((o.opacityTo - o.opacity) / 4));

                o.setOpacity(diff);

                if(Math.abs(o.opacityTo - diff) > 3) {
                        o.fadeTimer = window.setTimeout(function () { o.fade(); }, 50);
                } else {
                        o.setOpacity(o.opacityTo);
                        if(o.opacityTo == 0) o.div.style.display = "none";
                }
        };
        o.killEvent = function(e) {
                if (e == null) e = document.parentWindow.event;

                if (e.stopPropagation) {
                        e.stopPropagation();
                        e.preventDefault();
                }
                /*@cc_on@*/
                /*@if(@_win32)
                e.cancelBubble = true;
                e.returnValue = false;
                /*@end@*/
                return false;
        };
        o.startTimer = function () {
                if (o.timerSet) o.stopTimer();
                o.timer = window.setTimeout(function () { o.onTimer(); }, o.timerInc);
                o.timerSet = false;
        };
        o.stopTimer = function () {
                if (o.timer != null) window.clearTimeout(o.timer);
                o.timerSet = false;
        };
        o.events = {
                onkeydown: function (e) {

                        if(!o.visible) return true;

                        if (e == null) e = document.parentWindow.event;
                        var kc = e.keyCode ? e.keyCode : e.charCode;

                        if ( kc == 13 ) {
                                // close with update
                                o.returnFormattedDate();
                                o.hide();
                                return o.killEvent(e);
                        } else if ( kc == 27 ) {
                                // close
                                o.hide();
                                return o.killEvent(e);
                        } else if ( kc == 32 || kc == 0 ) {
                                // close
                                o.date =  new Date( );
                                o.updateTable();
                                return o.killEvent(e);
                        }

                        // Internet Explorer fires the keydown event faster than the JavaScript engine can
                        // update the interface. The following attempts to fix this.

                        /*@cc_on@*/
                        /*@if(@_win32)
                                if(new Date().getTime() - o.interval.getTime() < 100) return o.killEvent(e);
                                o.interval = new Date();
                        /*@end@*/

                        if ((kc > 49 && kc < 56) || (kc > 97 && kc < 104)) {
                                if (kc > 96) kc -= (96-48);
                                kc -= 49;
                                o.firstDayOfWeek = (o.firstDayOfWeek + kc) % 7;
                                o.updateTable();
                                return o.killEvent(e);
                        }
                        
                        if ( kc < 37 || kc > 40 ) return true;

                        var d = new Date( o.date ).valueOf();

                        if ( kc == 37 ) {
                                // ctrl + left = previous month
                                if( e.ctrlKey ) {
                                        d = new Date( o.date );
                                        d.setDate( Math.min(d.getDate(), datePicker.getDaysPerMonth(d.getMonth() - 1,d.getFullYear())) ); // no need to catch dec -> jan for the year
                                        d.setMonth( d.getMonth() - 1 );
                                } else {
                                        d -= 24 * 60 * 60 * 1000;
                                }
                        } else if ( kc == 39 ) {
                                // ctrl + right = next month
                                if( e.ctrlKey ) {
                                        d = new Date( o.date );
                                        d.setDate( Math.min(d.getDate(), datePicker.getDaysPerMonth(d.getMonth() + 1,d.getFullYear())) ); // no need to catch dec -> jan for the year
                                        d.setMonth( d.getMonth() + 1 );
                                } else {
                                        d += 24 * 60 * 60 * 1000;
                                }
                        } else if ( kc == 38 ) {
                                // ctrl + up = next year
                                if( e.ctrlKey ) {
                                        d = new Date( o.date );
                                        d.setDate( Math.min(d.getDate(), datePicker.getDaysPerMonth(d.getMonth(),d.getFullYear() + 1)) ); // no need to catch dec -> jan for the year
                                        d.setFullYear( d.getFullYear() + 1 );
                                } else {
                                        d -= 7 * 24 * 60 * 60 * 1000;
                                }
                        } else if ( kc == 40 ) {
                                // ctrl + down = prev year
                                if( e.ctrlKey ) {
                                        d = new Date( o.date );
                                        d.setDate( Math.min(d.getDate(), datePicker.getDaysPerMonth(d.getMonth(),d.getFullYear() - 1)) ); // no need to catch dec -> jan for the year
                                        d.setFullYear( d.getFullYear() - 1 );
                                } else {
                                        d += 7 * 24 * 60 * 60 * 1000;
                                }
                        }

                        o.date =  new Date( d );
                        o.updateTable();

                        return o.killEvent(e);
                },
                onmousedown: function(e) {
                        if ( e == null ) e = document.parentWindow.event;
                        var el = e.target != null ? e.target : e.srcElement;
                        if(el.tagName.toUpperCase() == "BUTTON" || (el.tagName.toUpperCase() == "TD" && el.className != "") || (el.tagName.toUpperCase() == "TH" && el.className != "")) return false;

                        datePickerController.hideAll();
                },
                onmouseover: function(e) { this.className += " date-picker-hover"; },
                onmouseout: function(e)  { this.className = this.className.replace(/date-picker-hover/g, ''); },
                onclick: function (e) {
                        if ( e == null ) e = document.parentWindow.event;
                        var el = e.target != null ? e.target : e.srcElement;
                        while ( el.nodeType != 1 ) el = el.parentNode;

                        var d = new Date( o.date );
                        var n = Number( el.firstChild.data );

                        if(isNaN(n)) {
                                o.hide();
                                return;
                        }

                        d.setDate( n );
                        o.date = d;

                        o.returnFormattedDate();
                        o.hide();
                },
                incDec:function(e) {
                        if(o.timerSet) {
                                o.stopTimer();
                        }
                        o.timerInc      = 1000;
                        o.dayInc        = arguments[1];
                        o.yearInc       = arguments[2];
                        o.monthInc      = arguments[3];
                        o.onTimer();
                        return o.killEvent(e);
                },
                clearTimer:function() {
                        o.stopped       = true;
                        o.timerInc      = 1000;
                        o.yearInc       = 0;
                        o.monthInc      = 0;
                        o.dayInc        = 0;
                        o.stopTimer();
                }
        };
        o.onTimer = function() {
                var d = new Date( o.date );

                d.setDate( Math.min(d.getDate()+o.dayInc, datePicker.getDaysPerMonth(d.getMonth()+o.monthInc,d.getFullYear()+o.yearInc)) ); // no need to catch dec -> jan for the year
                d.setMonth( d.getMonth() + o.monthInc );
                d.setFullYear( d.getFullYear() + o.yearInc );

                o.date = d;

                if(o.timerInc > 50) {
                        o.timerInc = 50 + Math.round(((o.timerInc - 50) / 1.8));
                }
                o.startTimer();
                o.updateTable();
        };
        o.setFirstDayOfWeek = function(e) {
                if ( e == null ) e = document.parentWindow.event;
                var elem = e.target != null ? e.target : e.srcElement;

                if(elem.tagName.toUpperCase() != "TH") {
                        while(elem.tagName.toUpperCase() != "TH") elem = elem.parentNode;
                }

                var cnt = 0;

                while(elem.previousSibling) {
                        elem = elem.previousSibling;
                        if(elem.tagName == "TH") cnt++;
                }

                o.firstDayOfWeek = (o.firstDayOfWeek + cnt) % 7;
                o.updateTable();

                return o.killEvent(e);
        };
        o.resize = function() {
                if(!o.created || !o.elem) return;

                var pos = datePicker.findPosition(o.elem);
                o.div.style.left = pos[0] + "px";
                o.div.style.top  = pos[1] + (o.elem.offsetHeight + 3) + "px";

                o.div.style.width = o.table.style.width = o.elem.offsetWidth + "px";
        };
        o.outOfRange = function(tmpDate) {

                if(!o.low && !o.high) return false;

                var level = false;
                if(!tmpDate) {
                        level = true;
                        tmpDate = o.date;
                }

                var d           = (tmpDate.getDate() < 10) ? "0" + tmpDate.getDate() : tmpDate.getDate();
                var m           = ((tmpDate.getMonth() + 1) < 10) ? "0" + (tmpDate.getMonth() + 1) : tmpDate.getMonth() + 1;
                var y           = tmpDate.getFullYear();
                var dt          = (y+' '+m+' '+d).replace(/ /ig,'');

                if(o.low) {
                        if(parseInt(dt) < parseInt(o.low)) {
                                if(!level) return true;
                                o.date = new Date( o.low.substr(4,2) + '/' + o.low.substr(6,2) + '/' + o.low.substr(0,4) );
                                return false;
                        }
                }
                if(o.high) {
                        if(parseInt(dt) > parseInt(o.high)) {
                                if(!level) return true;
                                o.date = new Date( o.high.substr(4,2) + '/' + o.high.substr(6,2) + '/' + o.high.substr(0,4) );
                        }
                }
                return false;
        };
        o.create = function() {
                /*@cc_on@*/
                /*@if(@_jscript_version < 6)
                        o.iePopUp = document.createElement('iframe');
                        o.iePopUp.src = "./js/blank.html";
                        o.iePopUp.setAttribute('className','iehack');
                        o.iePopUp.scrolling="no"
                        o.iePopUp.frameBorder="0"
                        o.iePopUp.name = o.iePopUp.id = "iePopUpHack";
                        document.body.appendChild(o.iePopUp);
                /*@end@*/

                if(typeof(fdLocale) == "object" && o.locale) {
                        datePicker.titles  = fdLocale.titles;
                        datePicker.months  = fdLocale.months;
                        datePicker.fullDay = fdLocale.fullDay;
                        // Optional parameters
                        if(fdLocale.dayAbbr) datePicker.dayAbbr = fdLocale.dayAbbr;
                        if(fdLocale.firstDayOfWeek) o.firstDayOfWeek = fdLocale.firstDayOfWeek;
                }

                o.div = document.createElement('div');
                o.div.style.zIndex = 9999;
                o.div.id = "fd-"+o.elem.name;
                var tableBody = document.createElement('tbody');
                var tableHead = document.createElement('thead');
                var nbsp = String.fromCharCode( 160 );

                o.table = document.createElement('table');
                o.div.className= "datePicker"

                var tr = document.createElement('tr');
                var th = document.createElement('th');

                // previous year
                var tmpelem = document.createElement('button');
                tmpelem.setAttribute("type", "button");
                tmpelem.className = "prev-but";
                tmpelem.appendChild(document.createTextNode('\u00AB'));
                tmpelem.title = datePicker.titles[2];
                tmpelem.onmousedown = function(e) { this.blur(); o.events.incDec(e,0,-1,0); }
                tmpelem.onmouseup = o.events.clearTimer;
                th.appendChild( tmpelem );

                // previous month
                var tmpelem = document.createElement('button');
                tmpelem.setAttribute("type", "button");
                tmpelem.className = "prev-but";
                tmpelem.appendChild(document.createTextNode("\u2039"));
                tmpelem.title = datePicker.titles[0];
                tmpelem.onmousedown = function(e) { this.blur(); o.events.incDec(e,0,0,-1); }
                tmpelem.onmouseup = o.events.clearTimer;
                th.appendChild( tmpelem );
                tr.appendChild( th );

                // title bar
                o.titleBar = document.createElement('th');
                o.titleBar.setAttribute('colSpan','5');
                o.titleBar.setAttribute('text-align','center');
                tr.appendChild( o.titleBar );

                th = document.createElement('th');

                // next month
                var tmpelem = document.createElement('button');
                tmpelem.setAttribute("type", "button");
                tmpelem.className = "next-but";
                tmpelem.appendChild(document.createTextNode('\u203A'));
                tmpelem.title = datePicker.titles[1];
                tmpelem.onmousedown = function(e) { this.blur(); o.events.incDec(e,0,0,1); }
                tmpelem.onmouseup = o.events.clearTimer;

                th.appendChild( tmpelem );

                // next year
                var tmpelem = document.createElement('button');
                tmpelem.setAttribute("type", "button");
                tmpelem.className = "next-but";
                tmpelem.appendChild(document.createTextNode('\u00BB'));
                tmpelem.title = datePicker.titles[3];
                tmpelem.onmousedown = function(e) { this.blur(); o.events.incDec(e,0,1,0); }
                tmpelem.onmouseup = o.events.clearTimer;
                th.appendChild( tmpelem );

                tr.appendChild( th );

                tableHead.appendChild(tr);

                var row, col;

                for(var rows = 0; rows < 7; rows++) {
                        row = document.createElement('tr')
                        for(var cols = 0; cols < 7; cols++) {
                                col = (rows == 0) ? document.createElement('th') : document.createElement('td');
                                if(rows != 0) {
                                        col.appendChild(document.createTextNode(nbsp));
                                } else {
                                        col.className = "date-picker-day-header";
                                }

                                row.appendChild(col);
                        }
                        if(rows != 0) tableBody.appendChild(row);
                        else          tableHead.appendChild(row);
                }
                o.table.appendChild( tableHead );
                o.table.appendChild( tableBody );
                o.div.appendChild( o.table );
                o.created = true;

                document.getElementsByTagName('body')[0].appendChild( o.div );
        };
        o.setDateFromInput = function() {
                var date = o.elem.value;

                if(date.match(/^[0-9]{4}$/)) {
                        if(date > 1600 && date < 2030) {
                                o.date.setFullYear(date);
                                return;
                        }
                }

                var dates = date.split(o.divider);

                if(dates.length != 3) {
                        o.date = new Date();
                        return;
                }

                var d,m,y,dt;

                d = o.format.replace(/-/g,'').indexOf('d');
                m = o.format.replace(/-/g,'').indexOf('m');
                y = o.format.replace(/-/g,'').indexOf('y');

                dt = dates[m] + "/" + dates[d] + "/" + dates[y];

                if(new Date( dt ) == 'Invalid Date'){
                        o.date = new Date();
                        return;
                }

                o.date.setMonth(dates[m]-1);
                o.date.setFullYear(dates[y]);
                o.date.setDate(dates[d]);
        };
        o.returnFormattedDate = function() {
                var d           = (o.date.getDate() < 10) ? "0" + o.date.getDate() : o.date.getDate();
                var m           = ((o.date.getMonth() + 1) < 10) ? "0" + (o.date.getMonth() + 1) : o.date.getMonth() + 1;
                var yyyy        = o.date.getFullYear();

                o.elem.value = o.format.replace('y',yyyy).replace('m',m).replace('d',d).replace(/-/g,o.divider);

                o.elem.focus();
                // Setting the input value with javascript does not invoke the onchange event
                // handler so we do it ourselves (in case other scripts have a handle on it).
                if(o.elem.onchange) o.elem.onchange();
        };
        // Credit where credit's due:

        // Most of the logic for this method from the webfx date-picker
        // http://webfx.eae.net/

        o.updateTable = function() {

                var i;
                var str = "";
                var rows = 6;
                var cols = 7;
                var currentWeek = 0;
                var nbsp = String.fromCharCode( 160 );

                var cells = new Array( rows );
                o.matrix = new Array( rows );
                for ( i = 0; i < rows; i++ ) {
                        cells[i] = new Array( cols );
                        o.matrix[i] = new Array( cols );
                }

                o.outOfRange();

                // Set the tmpDate to this month
                var tmpDate = new Date( o.date.getFullYear(), o.date.getMonth(), 1 );
                var today = new Date();

                // titleBar
                var titleText = datePicker.months[o.date.getMonth()] + nbsp + o.date.getFullYear();
                while(o.titleBar.firstChild) o.titleBar.removeChild(o.titleBar.firstChild);
                o.titleBar.appendChild(document.createTextNode(titleText));

                for ( i = 1; i < 32; i++ ) {
                        tmpDate.setDate( i );
                        var weekDay = ( tmpDate.getDay() + 6 ) % 7;

                        var colIndex = ( (weekDay - o.firstDayOfWeek) + 7 ) % 7;
                        if ( tmpDate.getMonth() == o.date.getMonth() ) {

                                var isToday = tmpDate.getDate() == today.getDate() &&
                                              tmpDate.getMonth() == today.getMonth() &&
                                              tmpDate.getFullYear() == today.getFullYear();

                                cells[currentWeek][colIndex] = { text: "", className: "" };

                                if ( o.date.getDate() == tmpDate.getDate())
                                        cells[currentWeek][colIndex].className += " date-picker-selected";
                                if ( isToday )
                                        cells[currentWeek][colIndex].className += " date-picker-today";
                                for( d = 0 ;d < o.highlightDays.length; d++ ) {
                                        if(weekDay == o.highlightDays[d]) {
                                                cells[currentWeek][colIndex].className += " date-picker-highlight";
                                        }
                                }

                                if(o.outOfRange(tmpDate)) {
                                        cells[currentWeek][colIndex].className = "out-of-range";
                                }

                                cells[currentWeek][colIndex].text = o.matrix[currentWeek][colIndex] = tmpDate.getDate();
                                if ( colIndex == 6 ) currentWeek++;
                        }
                }

                // Table headers
                var lnk, d;
                var ths = o.table.getElementsByTagName('thead')[0].getElementsByTagName('tr')[1].getElementsByTagName('th');
                for ( var y = 0; y < ths.length; y++ ) {
                        d = (o.firstDayOfWeek + y) % 7;

                        while(ths[y].firstChild) ths[y].removeChild(ths[y].firstChild);

                        ths[y].title = datePicker.fullDay[d];

                        // Don't create a button for the first day header
                        if(y > 0) {
                                but = document.createElement("BUTTON");
                                but.className = "fd-day-header";
                                but.onclick = but.onkeypress = ths[y].onclick = o.setFirstDayOfWeek;
                                but.appendChild(document.createTextNode(datePicker.dayAbbr ? datePicker.dayAbbr[d] : datePicker.fullDay[d].charAt(0)));
                                ths[y].appendChild(but);
                                but.title = datePicker.fullDay[d];
                        } else {
                                ths[y].appendChild(document.createTextNode(datePicker.dayAbbr ? datePicker.dayAbbr[d] : datePicker.fullDay[d].charAt(0)));
                                ths[y].onclick = null;
                        }
                }

                var trs = o.table.getElementsByTagName('tbody')[0].getElementsByTagName('tr');

                var tmpCell;

                for ( var y = 0; y < rows; y++ ) {
                        var tds = trs[y].getElementsByTagName('td');
                        for (var x = 0; x < cols; x++) {
                                tmpCell = tds[x];

                                while(tmpCell.firstChild) tmpCell.removeChild(tmpCell.firstChild);

                                if ( typeof cells[y][x] != "undefined" ) {
                                        tmpCell.className = cells[y][x].className;
                                        tmpCell.appendChild(document.createTextNode(cells[y][x].text));
                                        if(cells[y][x].className != "out-of-range") {
                                                tmpCell.onmouseover = o.events.onmouseover;
                                                tmpCell.onmouseout = o.events.onmouseout;
                                                tmpCell.onclick = o.events.onclick;
                                        } else {
                                                tmpCell.onmouseover = tmpCell.onmouseout = null;
                                                tmpCell.onclick = function() { o.hide(); }
                                        }
                                } else {
                                        tmpCell.className = "";
                                        tmpCell.onmouseover = tmpCell.onmouseout = null;
                                        tmpCell.onclick = function() { o.hide(); }
                                        tmpCell.appendChild(document.createTextNode(nbsp));
                                }
                        }
                }
        };
        o.init = function() {
                o.resize();
                o.setDateFromInput();

                o.fade();
                o.ieHack(true);
        };
        o.ieHack = function(cleanup) {
                // IE hack
                if(o.iePopUp) {
                        o.iePopUp.style.display = "block";
                        o.iePopUp.style.top = (o.div.offsetTop + 2) + "px";
                        o.iePopUp.style.left = o.div.offsetLeft + "px";
                        o.iePopUp.style.width = o.div.clientWidth + "px";
                        o.iePopUp.style.height = (o.div.clientHeight - 2) + "px";
                        if(cleanup) o.iePopUp.style.display = "none";
                }
        };
        o.show = function() {
                if(o.elem.disabled || o.visible) return;
                o.resize();
                o.setDateFromInput();
                o.updateTable();
                o.ieHack(false);

                datePickerController.addEvent(document, "mousedown", o.events.onmousedown);
                datePickerController.addEvent(document, "keypress", o.events.onkeydown);

                // Dumbass Internet Explorer requires the keydown event in order to catch arrow key events

                /*@cc_on@*/
                /*@if(@_win32)
                        datePickerController.removeEvent(document, "keypress", o.events.onkeydown);
                        datePickerController.addEvent(document, "keydown", o.events.onkeydown);
                /*@end@*/

                if(!o.visible) {
                        o.opacityTo = 90;
                        o.div.style.display = "block";
                        o.ieHack(false);
                        o.fade();
                        o.visible = true;
                }
        };
        o.hide = function()   {
                try {
                        datePickerController.removeEvent(document, "mousedown", o.events.onmousedown);
                        datePickerController.removeEvent(document, "keypress", o.events.onkeydown);
                        datePickerController.removeEvent(document, "keydown", o.events.onkeydown);
                } catch(e) {

                }
                if(o.iePopUp) {
                        o.iePopUp.style.display = "none";
                }
                o.opacityTo = 0;
                o.fade();
                o.visible = false;
        };
        o.create();
        o.init();
        datePickerController.addEvent(window, 'resize', o.resize);
}

datePickerController = {
        datePickers: [],

        hideAll: function(exemption) {
                for(var i=0, dp; dp = datePickerController.datePickers[i]; i++) {
                        if(i != exemption) dp.hide();
                }
        },
        dateFormat: function(dateIn) {

                var y, m, d, res;


                // dd-mm-yyyy
                if(dateIn.match(/^(0[1-9]|[12][0-9]|3[01])([- \/.])(0[1-9]|1[012])([- \/.])(\d\d?\d\d)$/)) {
                        res = dateIn.match(/^(0[1-9]|[12][0-9]|3[01])([- \/.])(0[1-9]|1[012])([- \/.])(\d\d?\d\d)$/);
                        y = res[5];
                        m = res[3];
                        d = res[1];
                // mm-dd-yyyy
                } else if(dateIn.match(/^(0[1-9]|1[012])([- \/.])(0[1-9]|[12][0-9]|3[01])([- \/.])(\d\d?\d\d)$/)) {
                        res = dateIn.match(/^(0[1-9]|1[012])([- \/.])(0[1-9]|[12][0-9]|3[01])([- \/.])(\d\d?\d\d)$/);
                        y = res[5];
                        m = res[1];
                        d = res[3];
                // yyyy-mm-dd
                } else if(dateIn.match(/^(\d\d?\d\d)([- \/.])(0[1-9]|1[012])([- \/.])(0[1-9]|[12][0-9]|3[01])$/)) {
                        res = dateIn.match(/^(\d\d?\d\d)([- \/.])(0[1-9]|1[012])([- \/.])(0[1-9]|[12][0-9]|3[01])$/);
                        y = res[1];
                        m = res[3];
                        d = res[5];
                } else return 0;

                if(m.length == 1) m = "0" + m;
                if(d.length == 1) d = "0" + d;
                if(y.length != 4) y = (parseInt(y) < 50) ? '20' + y : '19' + y;

                return y+m+d;
        },
        addEvent: function(obj, type, fn) {
                if( obj.attachEvent ) {
                        obj["e"+type+fn] = fn;
                        obj[type+fn] = function(){obj["e"+type+fn]( window.event );}
                        obj.attachEvent( "on"+type, obj[type+fn] );
                } else
                        obj.addEventListener( type, fn, true );
        },
        removeEvent:function(obj, type, fn) {
                if( obj.detachEvent ) {
                        obj.detachEvent( "on"+type, obj[type+fn] );
                        obj[type+fn] = null;
                } else
                        obj.removeEventListener( type, fn, true );
        },
        create: function() {
                if(!datePicker.isSupported) return;

                var inputs = document.getElementsByTagName('input');

                var regExp3 = /highlight-days-([0-6]){1,7}/g;           // the days to highlight in red
                var regExp4 = /range-low-([0-9\-]){10}/g;               // the lowest selectable date
                var regExp5 = /range-high-([0-9\-]){10}/g;              // the highest selectable date
                var regExp6 = /format-([dmy\-]{5})/g;                   // the input/output date format
                var regExp7 = /divider-(dot|slash|space|dash)/g;        // the character used to divide the date
                var regExp8 = /no-locale/g;                             // do not attempt to detect the browser language

                var format, divider, firstDayOfWeek, highlightDays;

                for(var i=0, inp; inp = inputs[i]; i++) {
                        if(inp.className && inp.className.search(regExp6) != -1 && inp.type == "text") {
                                if(document.getElementById('fd-'+inp.name)) continue;

                                var len = datePickerController.datePickers.length;

                                var options = {
                                        elem:inp,
                                        low:"",
                                        high:"",
                                        divider:"/",
                                        format:"d-m-y",
                                        highlightDays:[5,6],
                                        locale:inp.className.search(regExp8) == -1
                                };

                                // Date format(variations of d-m-y)
                                if(inp.className.search(regExp6) != -1) {
                                        options.format = inp.className.match(regExp6)[0].replace('format-','');
                                };

                                // What divider to use, a "/", "-", "." or " "
                                if(inp.className.search(regExp7) != -1) {
                                        var divider = inp.className.match(regExp7)[0].replace('divider-','');
                                        switch(divider.toLowerCase()) {
                                                case "dot":
                                                        options.divider = ".";
                                                        break;
                                                case "space":
                                                        options.divider = " ";
                                                        break;
                                                case "dash":
                                                        options.divider = "-";
                                                        break;
                                                default:
                                                        options.divider = "/";
                                        };
                                };

                                // The days to highlight
                                if(inp.className.search(regExp3) != -1) {
                                        var tmp = inp.className.match(regExp3)[0].replace(/highlight-days-/, '');
                                        options.highlightDays = new Array();
                                        for(var j = 0; j < tmp.length; j++) {
                                                options.highlightDays[options.highlightDays.length] = tmp.charAt(j);
                                        };
                                };

                                // The lower limit
                                if(inp.className.search(regExp4) != -1) {
                                        options.low = datePickerController.dateFormat(inp.className.match(regExp4)[0].replace(/range-low-/, ''));
                                        if(options.low == 0) {
                                                options.low = '';
                                        };
                                };

                                // The higher limit
                                if(inp.className.search(regExp5) != -1) {
                                        options.high = datePickerController.dateFormat(inp.className.match(regExp5)[0].replace(/range-high-/, ''));
                                        if(options.high == 0) {
                                                options.high = '';
                                        };
                                };

                                var but = document.createElement('button');
                                but.setAttribute("type", "button");
                                but.className = "date-picker-control";
                                but.id = "fd-but-" + len;

                                but.appendChild(document.createTextNode(String.fromCharCode( 160 )));
                                but.onclick = but.onpress = function() {
                                        var butId = this.id.replace('fd-but-','');
                                        datePickerController.hideAll(butId);
                                        datePickerController.datePickers[butId].show();
                                        this.blur();
                                        return false;
                                };

                                if(inp.nextSibling) {
                                        inp.parentNode.insertBefore(but, inp.nextSibling);
                                } else {
                                        inp.parentNode.appendChild(but);
                                };

                                datePickerController.datePickers[len] = new datePicker(options);
                        }
                }
        }

};


})();

datePickerController.addEvent(window, 'load', datePickerController.create);


