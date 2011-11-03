;;;; plugins.lisp

(in-package #:harlie)

(defvar *plugins* (make-hash-table :test 'equal))

(defclass plugin-request ()
  ((plugin-context :initarg :plugin-context :accessor plugin-context)
   (plugin-cmd :initarg :botcmd :accessor plugin-cmd)
   (plugin-conn :initarg :connection :accessor plugin-conn)
   (plugin-channel-name :initarg :channel-name :accessor plugin-channel-name)
   (plugin-reply-to :initarg :reply-to :accessor plugin-reply-to)
   (plugin-token-text-list :initarg :token-text-list :accessor plugin-token-text-list)
   (plugin-action :initarg :action :initform :run :accessor plugin-action)))

(defclass plugin ()
  ((plugin-name :initarg :plugin-name :accessor plugin-name)
   (plugin-hook :initarg :plugin-hook :accessor plugin-hook)
   (plugin-doc :initform nil :accessor plugin-doc)))

;; *doublehelp* is the fallback plugin which gives documentation on a failed lookup.

(defparameter *doublehelp*
  (make-instance 'plugin
		 :plugin-name "DOUBLEHELP"
		 :plugin-hook #'(lambda (plug-request)
				  (cond ((eq (action plug-request) :docstring)
					 (list (format nil "Sorry, I don't recognize that command.")
					       (format nil "  Try ~A for a list of commands." (make-short-url-string (plugin-context plug-request) "help"))))
					(t nil)))))

(defmacro defplugin (funame args &rest body)
  `(setf (gethash (symbol-name (quote ,funame)) *plugins*)
	 (make-instance 'plugin :plugin-name (symbol-name (quote ,funame))
				:plugin-hook #'(lambda (,@args) ,@body))))

;; So here's the new drill:
;; plugins are expected to respond to the protocol exemplified in sources.
;; If (plugin-action plug-request) is :docstring, then return a documentation string.
;; If (plugin-action plug-request) is :priority, then return a float representing
;; the position of this plugin among all the plugins.
;;
;; In the help page, plugins are listed in numeric order by priority,
;; and by name within priority.
;;
;; Plugins with priorities <= 0.0 are not listed on the help page,
;; but you can still get online help for them with the !help command.
;;
;; On the help page, there's a small vertical break between groups of
;; plugins at integer intervals.  Hence, the plugins with priorities
;; in the range [1.0, 2.0) will be listed in one block, and those in
;; [2.0, 3.0) will be listed in another, etc.  This lets you group
;; plugins together by general type and micromanage their order within
;; a group if you wish.

(defplugin sources (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Tell us where the source is kept."))
    (:priority -1.0)
    (:run (format nil "git@coruscant.deepsky.com:harlie.git"))))

(defplugin status (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Give the count of phrases in the chaining database"))
    (:priority 1.0)
    (:run (format nil "I know ~A phrases."
		  (count-phrases (plugin-context plug-request))))))

(defplugin conv (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Convert between currencies.  Usage: !conv <amount> <from-abbrev> <to-abbrev>"))
    (:priority 2.0)
    (:run (let* ((amount (second (plugin-token-text-list plug-request)))
		 (from (string-upcase (third (plugin-token-text-list plug-request))))
		 (to (string-upcase (fourth (plugin-token-text-list plug-request)))))
	    (if (string= from to)
		(format nil "Converting ~A to ~A is redundant." from to)
		(format nil "~{~A~^ = ~}"
			(find-forex
			 (fetch-formatted-url
			  "http://www.xe.com/ucc/convert/?Amount=~A&From=~A&To=~A"
			  amount from to))))))))

(defun parse-stock (tick)
  (cond ((string= tick "N/A") nil)
	((float-as-string-p tick) (parse-number tick))
	((or (every #'alpha-char-p tick) (some #'alphanumericp tick)) tick)
	(t nil)))

(defplugin stock (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Get a vaguely timely appraisal of the trading value of a given stock, by symbol"))
    (:priority 2.0)
    (:run (let* ((symbol (string-upcase (second (plugin-token-text-list plug-request))))
		 (quote (loop for i in (get-stock-values symbol)
			      :collect (parse-stock i))))
	    (if (every #'identity quote)
		(format nil "Issue: ~A last traded for $~$ at ~A on ~A, ~A changed on the day. Opened at $~$ with a high of $~$ and a low of $~$. ~:D shares traded."
			(first quote) (second quote) (fourth quote) (third quote)
			(fifth quote) (sixth quote) (seventh quote) (eighth quote) (ninth quote))
		(format nil "No quotes for symbole: ~A. Perhaps you mistyped?" symbol))))))

(defplugin jcw (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Address the left/right libertarian/asshole continuum"))
    (:priority 4.0)
    (:run (format nil "FUCK YOU, JACKHOLE!"))))

(defplugin rally (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Deal with the world of racing"))
    (:priority 4.0)
    (:run (format nil "FUCK YOU, HANS!"))))

(defplugin f1 (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "He's such a fucking nancyboy."))
    (:priority 4.0)
    (:run (format nil "FUCK YOU, SCHUMACHER!"))))

(defplugin spew (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "What's the secret word for tonight?"))
    (:priority -1.0)
    (:run (list "I'm a mouthy bastard" "Who can't get everything" "He wants to say" "In one line."))))

(defplugin ccode (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Look up a country code based on a search string.  Usage: !ccode <substring>"))
    (:priority 3.0)
    (:run (let* ((country (second (plugin-token-text-list plug-request)))
		 (countries (country-lookup country)))
	    (if (and countries (listp countries))
		(loop for (a . b) in countries
		      :collect (format nil "[ ~a ][ ~a ]" a b))
		(format nil "No match for search term: ~A" country))))))

(defplugin area (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Look up an area code.  Usage: !area <area code>"))
    (:priority 3.0)
    (:run (let* ((searchterm (second (plugin-token-text-list plug-request)))
		 (area (areacode-lookup searchterm)))
	    (if (and area (listp area))
		(loop for (a . b) in area
		      :collect (format nil "[ ~A ][ ~A ]" a b))
		(format nil "No area code found for your search term: ~A" searchterm))))))

(defplugin iata (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Look up an airport description by its IATA code.  Usage: !iata <airport code>"))
    (:priority 3.0)
    (:run (let* ((searchterm (second (plugin-token-text-list plug-request)))
		 (airports (airport-lookup searchterm)))
	    (if (and airports (listp airports))
		(loop for (a . b) in airports
		      :collect (format nil "[ ~A ][ ~A ]" a b))
		(format nil "No match for your airport: ~A" searchterm))))))

(defplugin ciso (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Look up an ISO currency code.  Usage: !ciso <substring>"))
    (:priority 2.0)
    (:run (let* ((searchterm (second (plugin-token-text-list plug-request)))
		 (curr (currency-lookup searchterm)))
	    (if (and curr (listp curr))
		(loop for (a . b) in curr
		      :collect (format nil "[ ~A ][ ~A ]" a b))
		(format nil "~A" curr))))))

(defplugin rate (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Look up the conversion rate between two currencies.  Usage: !rate <curr1> <curr2>"))
    (:priority 2.0)
    (:run (let* ((amount 1)
		 (from (string-upcase (second (plugin-token-text-list plug-request))))
		 (to (string-upcase (third (plugin-token-text-list plug-request)))))
	    (if (string= from to)
		(format nil "The rate of ~A in ~A is obvious." from to)
		(progn
		  (let* ((fx
			   (break-on-no-break-space
			    (find-forex (fetch-formatted-url
					 "http://www.xe.com/ucc/convert/?Amount=~A&From=~A&To=~A"
					 amount from to))))
			 (c1amt (parse-number:parse-number
				 (remove #\, (first (first fx)))))
			 (curr1 (second (first fx)))
			 (c2amt (parse-number:parse-number
				 (remove #\, (first (second fx)))))
			 (curr2 (second (second fx)))
			 (c1->c2 (format nil " ~$ ~A  =  ~$ ~A "
					 c1amt curr1 c2amt curr2))
			 (c2->c1 (format nil " ~$ ~A  =  ~$ ~A "
					 amount curr2 (/ c1amt c2amt ) curr1)))
		    (format nil "[ ~A | ~A ]" c1->c2 c2->c1))))))))

(defplugin babble (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Generate some ill-considered bot spew."))
    (:priority -1.0)
    (:run (format nil "~{~A~^ ~}" (chain (plugin-context plug-request))))))

(defplugin haiku (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "each utterance a / closed flower, capable of / independent life."))
    (:priority 1.5)
    (:run (progn
	    (format nil "~{~A~^ ~}" (make-haiku (plugin-context plug-request)))))))

(defplugin ftw (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "How do you like your victory?"))
    (:priority -1.0)
    (:run (format nil "VICTORY!  FLAWLESS!"))))

(defplugin trigger (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Return the current trigger word list"))
    (:priority 1.5)
    (:run (format nil "~{~A~^, ~}"
		  (trigger-list (gethash (plugin-channel-name plug-request)
					(channels (plugin-conn plug-request))))))))

(defplugin help (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Advertise how to get help with the bot's commands"))
    (:priority 1.0)
    (:run (if (> (length (plugin-token-text-list plug-request)) 1)
	      (funcall (plugin-hook
			(gethash (string-upcase (remove #\! (second (plugin-token-text-list plug-request)))) *plugins* *doublehelp*))
		       (make-instance 'plugin-request :action :docstring))
	      (list
	       (format nil "~A" (make-short-url-string (plugin-context plug-request) "help"))
	       (format nil "  or !help <command>"))))))

(defun html-help ()
  "Return HTML for a page giving help with the bot's plugin commands."
  (with-html-output-to-string (s)
    (:html
     (:head
      (:title (str (escape-string (format nil "Bot Help Page")))))
     (:body
      (:h1 (str (escape-string (format nil "Bot Command Help"))))
      (:dl
       (let ((oldpriority 0.0))
	 (dolist (doc (sort (plugin-docs) 'sort-docs))
	   (multiple-value-bind (n f) (floor (third doc))
	     (declare (ignore n))
	     (format t "~A ~A~%" oldpriority (third doc))
	     (if (> (third doc) 0.0)
		 (progn
		   (if (and (< oldpriority (third doc)) (= f 0.0))
		       (htm
			(:br)))
		   (htm
		    (:dt (:b (str (escape-string (format nil "!~A:" (first doc))))))
		    (:dd (str (escape-string (format nil "~A" (second doc))))))
		 (setf oldpriority (third doc))))))))))))

(defplugin 8ball (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Consult the Magic 8-Ball if you dare"))
    (:priority 4.0)
    (:run (format nil "~A" (consult-8ball)))))

(defplugin calc (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Unit conversion and other exciting things."))
    (:priority 2.0)
    (:run (let* ((search-tokens (mapcar 'url-encode (cdr (plugin-token-text-list plug-request))))
		 (calcresult (find-calc (fetch-formatted-url "http://www.google.com/search?q=~{~A~^+~}&client=ubuntu&channel=fs" search-tokens))))
	    calcresult))))

(defplugin pants (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Make the dicklicking face again"))
    (:priority 4.0)
    (:run (format nil "~{~A~^ ~}" (random-choice *bong-noises* (+ 3 (random 8)))))))

(defplugin doomsday (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Check the purity of essence of your precious bodily fluids"))
    (:priority 4.0)
    (:run (find-doomsday (fetch-formatted-url "http://www.thebulletin.org/")))))

(define-condition unrecognized-operator-error (error)
  ((unrecognized-operator :initarg :unrecognized-operator :initform nil :reader unrecognized-operator)))

(defparameter *unitconv* (acons '("CELSIUS" "FAHRENHEIT") '("9" "5" "/" "*" "32" "+") nil))

(defun rpn-calculator (l)
  (let ((stack nil))
    (handler-case
	(do* ((x (pop l) (pop l))
	      (opname (string-upcase x) (string-upcase x)))
	     ((not x) 	  (if (= (length stack) 1)
			      (if (integerp (caar stack))
				  (format nil "~A" (caar stack))
				  (format nil "~F" (caar stack)))
			      (format nil "Stack (top): [~{~A~^ ~}]" (maplist #'(lambda (x) (car x)) stack))))
		    (let ((opname (string-upcase x)))
		      (cond ((scan "^[0-9]+$" x)
			     (push (list (parse-integer x) nil) stack))
			    ((scan "^[0-9]*[.][0-9]+$" x)
			     (push (list (parse-number:parse-number x) nil) stack))
			    ((scan "^NEG$" opname)
			     (setf (caar stack) (- (caar stack))))
			    ((scan "^[+*]$" opname)
			     (push (list (funcall (intern opname) (car (pop stack)) (car (pop stack))) nil) stack))
			    ((scan "^[/-]|EXPT|LOG$" opname)
			     (let ((a (car (pop stack)))
				   (b (car (pop stack))))
			       (push (list (funcall (intern opname) b a) nil) stack)))
			    ((scan "^SIN|COS|TAN|ASIN|ACOS|ATAN|SQRT|EXP$" opname)
			     (push (list (funcall (intern opname) (car (pop stack))) nil) stack))
			    ((scan "^GCD|LCM$" opname)
			     (handler-case
				 (push (list (funcall (intern opname) (car (pop stack)) (car (pop stack))) nil) stack)
			       (type-error () (return-from rpn-calculator "Type error: expected integer."))))
			    ((scan "^RAND(OM)?$" opname)
			     (push (list (random (car (pop stack))) nil) stack))
			    ((scan "^LN$" opname)
			     (push (list (log (pop stack)) nil) stack))
			    (t (error 'unrecognized-operator-error
				      :unrecognized-operator x)))))

      (simple-type-error () (if (= (length stack) 0)
				 (format nil "Stack underflow.")
				 (format nil "Type error.")))
      (unrecognized-operator-error (x) (format nil "Unrecognized operator: ~A" (unrecognized-operator x))))))

(defplugin rpn (plug-request)
  (case (plugin-action plug-request)
    (:docstring (format nil "Do a little arithmetic in reverse Polish notation"))
    (:priority 3.0)
    (:run (rpn-calculator (rest (plugin-token-text-list plug-request))))))

;; ftoc

;; ctof

;; ===[ hyperspace motivator follows. ]===

(defun plugin-docs ()
  "Generate a list-of-lists from the plugin names, doc strings, and priorities."
  (loop for k being the hash-keys in *plugins*
	collecting (list k
			 (funcall (plugin-hook (gethash k *plugins*))
				  (make-instance 'plugin-request :action :docstring))
			 (funcall (plugin-hook (gethash k *plugins*))
				  (make-instance 'plugin-request :action :priority)))))

(defun sort-docs (a b)
  "Sort a list-of-lists of plugins by name within priority."
  (cond ((not (= (third a) (third b))) (< (third a) (third b)))
	((not (string= (first a) (first b))) (string< (first a) (first b)))
	(t nil)))

(defun run-plugin (plug-request)
  "Run a plugin's hook function and send the return text back to the requester."
  (let* ((plugname (string-upcase (subseq (plugin-cmd plug-request) 1)))
	 (plugf (gethash plugname *plugins* nil)))
    (if plugf
	(let ((reply (funcall (plugin-hook plugf) plug-request)))
	  (cond ((stringp reply)
		 (qmess (plugin-conn plug-request) (plugin-reply-to plug-request)
			(format nil "~A:: ~A" (string-downcase plugname) reply)))
		((listp reply)
		 (dolist (line reply)
		   (qmess (plugin-conn plug-request) (plugin-reply-to plug-request)
			  (format nil "~A:: ~A" (string-downcase plugname) line))))
		(t (qmess (plugin-conn plug-request) (plugin-reply-to plug-request)
			  (format nil "~A:: I'm a tragic victim of duck typing gone wrong." (string-downcase plugname))))))
	(qmess (plugin-conn plug-request) (plugin-reply-to plug-request) (format nil "~A: unknown command." (string-downcase plugname))))))
