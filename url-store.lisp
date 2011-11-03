;;;; url-store.lisp

(in-package :harlie)

(defclass url-store () ())

(defclass hash-url-store (url-store)
  ((url->short :initform (make-hash-table :test 'equal :synchronized t) :accessor url->short)
   (short->url :initform (make-hash-table :test 'equal :synchronized t) :accessor short->url)
   (url->headline :initform (make-hash-table :test 'equal :synchronized t) :accessor url->headline)))

(defclass postmodern-url-store (url-store)
  ((readonly-url-dbs :initform (config-psql-old-credentials *bot-config*) :accessor readonly-url-dbs)
   (readwrite-url-db :initform (config-psql-url-new-credentials *bot-config*) :accessor readwrite-url-db)))

(defvar *hash-url-store* (make-instance 'hash-url-store))

(defvar *pomo-url-store* (make-instance 'postmodern-url-store))

(defvar *the-url-store*
  (case (config-url-store-type *bot-config*)
    (:psql *pomo-url-store*)
    (:hash *hash-url-store*)
    (otherwise *hash-url-store*)))

(defgeneric get-url-from-old-shortstring (store url)
  (:documentation "Check the existing databases for entries corresponding to a given shortstring."))

(defmethod get-url-from-old-shortstring ((store postmodern-url-store) short)
  (dolist (db (readonly-url-dbs store))
    (with-connection db
      (let ((long
	      (query (sql (:select 'url :from 'urls :where (:= 'shorturl short))))))
        (when long (return (caar long)))))))

(defclass urls ()
  ((url-id :col-type integer :accessor url-id)
   (input-url :col-type string :initarg :input-url :accessor input-url)
   (redirected-url :col-type string :initarg :redirected-url :accessor redirected-url)
   (short-url :col-type string :initarg :short-url :accessor short-url)
   (title :col-type string :initarg :title :accessor title)
   (from-nick :col-type string :initarg :from-nick :accessor from-nick)
   (tstamp :col-type integer :initform (timestamp-to-unix (now)) :accessor tstamp)
   (dead :col-type boolean :initform nil :accessor url-dead-p)
   (context-id :col-type integer :initarg :context-id :accessor context-id))
  (:metaclass dao-class)
  (:keys url-id))

;;; some janitorial functions to mark urls that 404 'dead' in the
;;; database, and to try to ensure a title for each url.

(defun list-all-urls ()
  "return a list of urls dao objects, one for each url in the
   shortener db."
  (let ((dbconn (readwrite-url-db *the-url-store*)))
    (with-connection dbconn (select-dao 'urls "true order by random()"))))

(defun list-n-urls (n &key (urls (list-all-urls)))
  "take the first n urls retrieved from the urlstore. primarily to
   limit for testing other janitorial features."
  (loop for i to (1- n) ;; indexes start at 0. ask for 12, get 12.
	for url in urls
	:collect url))

(defun scan-urls-with-fn (fn &key (urls (list-all-urls)))
  "forex: (scan-urls-with-fn #'url-resolves-p :urls (list-n-urls 10))
   => (#<URLS {10045ED5A1}> #<URLS {10045EE191}> #<URLS {10045EF1F1}>
   #<URLS {10045EFDE1}> #<URLS {10131745F1}> 6 7 8 #<URLS
   {1013174671}> #<URLS {1013174691}>) [at time of this writing.]"
  (mapcar fn urls))

(defun url-resolves-p (urlobj)
  "the url resolves is the get status is not in the 400 range. If it
   resolves, return the url object, if it does not, return the url-id."
  (multiple-value-bind (page status) (webget (input-url urlobj))
    (declare (ignorable page))
    (cond
      ((and status (< status 400)) urlobj)
      (t (url-id urlobj)))))



(defparameter *letterz* "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

(defparameter *how-short* 5)

(defun make-shortstring ()
  "Generate a single random short-URL string."
  (apply #'concatenate 'string
	 (loop for i from 1 to *how-short* collecting
					   (string (elt *letterz* (random (length *letterz*)))))))

(defgeneric make-unique-shortstring (store url)
  (:documentation "Assign a new short URL string to URL."))

(defmethod make-unique-shortstring ((store hash-url-store) url)
  (sb-ext:with-locked-hash-table ((short->url store))
    (sb-ext:with-locked-hash-table ((url->short store))
      (do ((short (make-shortstring) (make-shortstring)))
	  ((not (gethash short (short->url store)))
	   (progn
	     (setf (gethash short (short->url store)) url)
	     (setf (gethash url (url->short store)) short)
	     short))))))

(defmethod make-unique-shortstring ((store postmodern-url-store) url)
  (with-connection (readwrite-url-db store)
    (do ((short (make-shortstring) (make-shortstring)))
	((not (query (:select '* :from 'urls :where (:= 'short-url short))))
	 short))))

(defgeneric lookup-url (store context url nick)
  (:documentation "Return present or new short URL and title for specified URL."))

(defun make-short-url-string (context hash)
  "Compose the short URL string for a given hash in a given context."
  (format nil "~A~A" (make-url-prefix (bot-web-server context) (bot-web-port context)) hash))

(defmethod lookup-url ((store hash-url-store) context url nick)
  (declare (ignore context nick))
  (let ((short (sb-ext:with-locked-hash-table ((url->short store))
		 (gethash url (url->short store)))))
    (if short
	(sb-ext:with-locked-hash-table ((url->headline store))
	  (values short (gethash url (url->headline store))))
	(multiple-value-bind (title message) (fetch-title url)
	  (cond (title
		 (progn
		   (setf short (make-unique-shortstring store url))
		   (sb-ext:with-locked-hash-table ((url->headline store))
		     (setf (gethash url (url->headline store)) title))
		   (values short title)))
		(message
		 (progn
		   (setf short (make-unique-shortstring store url))
		   (sb-ext:with-locked-hash-table ((url->headline store))
		     (setf (gethash url (url->headline store)) (format nil "~A: ~A" message url)))
		   (values short message)))
		(t (values nil nil)))
	  )
)))

(defmethod lookup-url ((store postmodern-url-store) context url nick)
  (format t "url-write-context-id: ~A~%" (url-write-context-id context))
  (let ((result (with-connection (readwrite-url-db store)
		  (query (:order-by
			  (:select 'short-url 'title
				   :from 'urls
				   :where (:= 'input-url url))
			  (:raw "tstamp desc"))))))
    (format t "Result: ~A~%" result)
    (if result
	(destructuring-bind (short title) (first result)
	  (values (make-short-url-string context short) title))
	(multiple-value-bind (title message) (fetch-title url)
	  (format t "Title: ~A    Message: ~A~%" title message)
	  (cond (title
		 (let ((short (make-unique-shortstring store url)))
		   (with-connection (readwrite-url-db store)
		     (insert-dao (make-instance 'urls :input-url url :redirected-url url :short-url short :title title :from-nick nick :context-id (url-write-context-id context)))
		     (values (make-short-url-string context short) title))))
		(message
		 (let ((short (make-unique-shortstring store url)))
		   (with-connection (readwrite-url-db store)
		     (insert-dao (make-instance 'urls :input-url url :redirected-url url :short-url short :title (format nil "~A: ~A" message url) :from-nick nick :context-id (url-write-context-id context)))
		     (values (make-short-url-string context short) message))))
		(t (values nil nil)))))))

(defgeneric get-url-from-shortstring (store short)
  (:documentation "Return the full URL associated with a given short string."))

(defmethod get-url-from-shortstring ((store hash-url-store) short)
  (sb-ext:with-locked-hash-table ((short->url store))
    (gethash short (short->url store))))

(defmethod get-url-from-shortstring ((store postmodern-url-store) short)
  (with-connection (readwrite-url-db store)
    (caar (query (:select 'input-url :from 'urls :where (:= 'short-url short))))))

(defgeneric get-urls-and-headlines (store context)
  (:documentation "Get a list of URLs and headlines from an URL store."))

(defmethod get-urls-and-headlines ((store hash-url-store) (context bot-context))
  (declare (ignore context))
  (sb-ext:with-locked-hash-table ((url->headline store))
    (loop for k being the hash-keys in (url->headline store)
	  collecting
	  (list k (gethash k (url->headline store) "Click here for a random link.")))))

(defmethod get-urls-and-headlines ((store postmodern-url-store) (context bot-context))
  (with-connection (readwrite-url-db store)
    (query (:order-by
	    (:select 'input-url 'title
		     :from 'urls
		     :where (:and
			     (:= 'context-id (url-read-context-id context))
			     (:not 'dead)) )
	    (:raw "tstamp desc")))))

(defparameter *suppress-url-encoding* t)

(defun fetch-formatted-url (url-string &rest args)
  "Retrieve the lhtml contents of the page at a specified URL.
Does format-style string interpolation on the url string."
  (chtml:parse
   (http-request
    (apply 'format nil url-string args))
   (chtml:make-lhtml-builder)))
