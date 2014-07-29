;;; names.el --- Namespaces for emacs-lisp. Works like C++ namespaces to avoid name clobbering.

;; Copyright (C) 2014 Artur Malabarba <bruce.connor.am@gmail.com>

;; Author: Artur Malabarba <bruce.connor.am@gmail.com>
;; URL: http://github.com/Bruce-Connor/names
;; Version: 0.5
;; Package-Requires: ((emacs "24.1") (cl-lib "1.0") (noflet "0.0.11"))
;; Keywords:
;; Prefix: names
;; Separator: -

;;; Commentary:
;;
;; The description is way too large to sanely write here. Please see
;; the URL: http://github.com/Bruce-Connor/names

;;; Instructions:
;;
;; INSTALLATION
;;
;; This package is available fom Melpa, you may install it by calling
;; M-x package-install RET names.
;;
;; Alternatively, you can download it manually, place it in your
;; `load-path' and require it with
;;
;;     (require 'names)

;;; License:
;;
;; This file is NOT part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 2
;; of the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;

;;; Change Log:
;; 0.1a - 2014/05/20 - Created File.
;;; Code:

(require 'cl-lib)

(eval-when-compile (require 'noflet))
(eval-when-compile (require 'edebug))

;;; Support
(unless (fboundp 'function-get)
  (defun function-get (f prop &optional autoload)
    "Return the value of property PROP of function F.
If AUTOLOAD is non-nil and F is autoloaded, try to autoload it
in the hope that it will set PROP.  If AUTOLOAD is `macro', only do it
if it's an autoloaded macro."
    (let ((val nil))
      (while (and (symbolp f)
                  (null (setq val (get f prop)))
                  (fboundp f))
        (let ((fundef (symbol-function f)))
          (if (and autoload (autoloadp fundef)
                   (not (equal fundef
                               (autoload-do-load fundef f
                                                 (if (eq autoload 'macro)
                                                     'macro)))))
              nil                         ;Re-try `get' on the same `f'.
            (setq f fundef))))
      val)))


;;; ---------------------------------------------------------------
;;; Variables
(defconst names-version "0.5" "Version of the names.el package.")

(defvar names--name nil
  "Name of the current namespace inside the `namespace' macro.")
(defvar names--regexp nil "Regexp matching `names--name'.")

(defvar names--bound nil
  "List of variables defined in this namespace.")
(defvar names--fbound nil
  "List of functions defined in this namespace.")
(defvar names--macro nil 
  "List of macros defined in this namespace.")

(defvar names--keywords nil
  "Keywords that were passed to the current namespace.
Current possible keywords are :let-vars :global :protection")

(defvar names--local-vars nil
  "Non-global vars that are let/lambda bound at the moment.
These won't be namespaced, as local takes priority over namespace.")

(defvar names--protection nil
  "Leading chars used to identify protected symbols.
Don't customise this.
Instead use the :protection keyword when defining the
namespace.")

(defvar names--current-run nil 
  "Either 1 or 2, depending on which runthrough we're in.")

(defvar names--var-list
  '(names--name names--regexp names--bound
                 names--macro names--current-run
                 names--fbound names--keywords
                 names--local-vars names--protection) 
  "List of variables the user shouldn't touch.")

(defvar names--inside-make-autoload nil 
  "Used in `make-autoload' to indicate to `define-namespace' that we're generating autoloads.")

(defmacro names--prepend (sbl)
  "Return namespace+SBL."
  (declare (debug (symbolp)))
  `(intern (format "%s%s" names--name ,sbl)))


(defmacro names--filter-if-bound (var &optional pred)
  "If VAR is bound and is a list, take the car of its elements which satify PRED."
  (declare (debug (symbolp function-form)))
  (when (boundp var)
    `(cl-remove-if
      ,pred (mapcar (lambda (x) (or (car-safe x) x)) ,var))))


;;; ---------------------------------------------------------------
;;; The Main Macro and Main Function.
;;;###autoload
(defmacro define-namespace (name &rest body)
  "Inside the namespace NAME, execute BODY.
NAME can be any symbol (not quoted), but it's highly recommended
to use some form of separator (such as :, /, or -).

This has two main effects:

1. Any definitions inside BODY will have NAME prepended to the
symbol given. Ex:
    (define-namespace foo:
    (defvar bar 1 \"docs\")
    )
expands to
    (defvar foo:bar 1 \"docs\")


2. Any function calls and variable names get NAME prepended to
them if possible. Ex:
    (define-namespace foo:
    (message \"%s\" my-var)
    )
expands to
    (foo:message \"%s\" foo:my-var)
but only if `foo:message' has a function definition. Similarly,
`my-var' becomes `foo:my-var', but only if `foo:my-var' has
a variable definition.

If `foo:message' is not a defined function, the above would
expand instead to
    (message \"%s\" foo:my-var)

===============================

AUTOLOAD

In order for `define-namespace' to work with ;;;###autoload
comments just replace all instances of ;;;###autoload inside your
`define-namespace' with `:autoload', and then add an ;;;###autoload
comment just above your `define-namespace'.

===============================

KEYWORDS

Immediately after NAME you may add keywords which customize the
behaviour of `define-namespace'. For a description of these keywords, see
the manual on
http://github.com/Bruce-Connor/names

\(fn NAME [KEYWORDS] BODY)"
  (declare (indent (lambda (&rest x) 0))
           (debug (&define name body)))
  (names--error-if-using-vars)
  (unwind-protect
      (let* ((names--name name)
             (names--regexp
              (concat "\\`" (regexp-quote (symbol-name name))))
             (names--current-run 0)
             ;; Use the :protection keyword to change this.
             (names--protection "\\`::")
             (names--bound
              (names--remove-namespace-from-list
               (names--filter-if-bound byte-compile-bound-variables)
               (names--filter-if-bound byte-compile-constants)
               (names--filter-if-bound byte-compile-variables)))
             (names--fbound
              (names--remove-namespace-from-list
               (names--filter-if-bound byte-compile-macro-environment 'macrop)
               (names--filter-if-bound byte-compile-function-environment 'macrop)))
             (names--macro
              (names--remove-namespace-from-list
               (names--filter-if-bound byte-compile-macro-environment (lambda (x) (not (macrop x))))
               (names--filter-if-bound byte-compile-function-environment (lambda (x) (not (macrop x))))))
             names--keywords names--local-vars)
        ;; Read keywords
        (while (and (keywordp (car-safe body))
                    ;; :autoload is part of body and is handled below.
                    (null (eq (car-safe body) :autoload)))
          (push (names--handle-keyword body) names--keywords)
          (setq body (cdr body)))
        ;; First have to populate the bound and fbound lists. So we read
        ;; the entire form (without evaluating it).
        (mapc 'names-convert-form body)
        (cl-incf names--current-run)
        ;; Then we go back and actually namespace the entire form, which
        ;; we return so that it can be evaluated.
        (cons 'progn (mapcar 'names-convert-form
                             ;; Unless we're in `make-autoload', then just return autoloads.
                             (if names--inside-make-autoload
                                 (names--extract-autoloads body)
                               body))))
    (mapc (lambda (x) (set x nil)) names--var-list)))

(defun names--extract-autoloads (body)
  "Return a list of the forms in BODY preceded by :autoload."
  (let (acons)
    (when (setq acons (memq :autoload body))
      (cons
       (cadr acons)
       (names--extract-autoloads (cdr (cdr acons)))))))

;;;###autoload
(defadvice make-autoload (before names-before-make-autoload-advice
                                 (form file &optional expansion) activate)
  "Make sure `make-autoload' understands `define-namespace'.
Use a letbind to indicate to `define-namespace' that we're generating autoloads."
  (let ((names--inside-make-autoload t)
        space)
    (when (eq (car-safe form) 'define-namespace)
      (setq space (macroexpand form))
      (ad-set-arg 0 space)
      (ad-set-arg 2 'expansion))))

(defun names-convert-form (form)
  "Do namespace conversion on FORM.
FORM is any legal elisp form.
Namespace name is defined by the global variable `names--name'.

See macro `namespace' for more information."
  (cond
   ((null form) form)
   ;; Function calls
   ((consp form)
    (let ((kar (car form))
          func)
      (cond
       ;; If symbol is protected, clean it.
       ((setq func (names--remove-protection kar))
        (names--message "Protected: %s" kar)
        ;; And decide what to do with it.
        (names--handle-args func (cdr form)))
       
       ;; If kar is a list, either 1) it's a lambda form, 2) it's a
       ;; macro we don't know about yet, 3) we have a bug.
       ((consp kar)
        (if (and (null (functionp kar))
                 (> names--current-run 1))
            (names--warn "Ran into the following strange form.
Either it's an undefined macro, a macro with a bad debug declaration, or we have a bug.\n%s" form)
          (mapcar 'names-convert-form form)))
       
       ;; Namespaced Functions/Macros
       ((names--fboundp kar)
        (names--message "Namespaced: %s" kar)
        (names--args-of-function-or-macro
         (names--prepend kar) (cdr form) (names--macrop kar)))
       
       ;; General functions/macros/special-forms
       (t (names--handle-args kar (cdr form))))))
   ;; Variables
   ((symbolp form)
    (names--message "Symbol handling: %s" form)
    ;; If symbol is protected, clean it and don't namespace it.
    (or (names--remove-protection form)
        ;; Otherwise, namespace if possible.
        (if (names--boundp form)
            (names--prepend form)
          form)))
   ;; Values
   (t form)))

(defun names--handle-args (func args)
  "Generic handling for the form (FUNC . ARGS), without namespacing FUNC."
  (let ((handler (intern (format "names--convert-%s" func))))
    ;; Some function-like forms get special handling.
    ;; That's anything with a names--convert-%s function defined.
    (if (fboundp handler)
        (progn (names--message "Special handling: %s" handler)
               (funcall handler (cons func args)))
      ;; If it isn't special, it's either a function or a macro.
      (names--args-of-function-or-macro func args (macrop func)))))

(defun names--message (f &rest rest)
  "If :verbose is on, pass F and REST to `message'."
  (when (names--keyword :verbose)
    (apply 'message (concat "[names] " f) rest)))

(defun names--warn (f &rest rest)
  "Pass F and REST to `message', unless byte-compiling."
  (unless (and (boundp 'byte-compile-function-environment)
               byte-compile-function-environment)
    (apply 'message (concat "[names] " f) rest)))


;;; ---------------------------------------------------------------
;;; Some auxiliary functions
(defun names--error-if-using-vars ()
  "Remind the developer that variables are not customizable."
  (mapcar
   (lambda (x)
     (when (eval x)
       (error "[names] Global value of variable %s should be nil! %s"
              x "Set it using keywords instead")))
   names--var-list))

(defun names--remove-namespace-from-list (&rest lists)
  "Return a concatenated un-namespaced version of LISTS.
Symbols in LISTS that aren't namespaced are removed, symbols that
are namespaced become un-namespaced."
  (delq nil (mapcar 'names--remove-namespace (apply 'append lists))))

(defun names--remove-namespace (symbol)
  "Return SYMBOL with namespace removed, or nil if S wasn't namespaced."
  (names--remove-regexp symbol names--regexp))

(defun names--remove-protection (symbol)
  "Remove the leading :: from SYMBOL if possible, otherwise return nil."
  (names--remove-regexp symbol names--protection))

(defun names--remove-regexp (s r)
  "Return S with regexp R removed, or nil if S didn't match."
  (let ((name (symbol-name s)))
    (when (string-match r name)
      (intern (replace-match "" nil nil name)))))

(defun names--quote-p (sbl)
  "Is SBL a function which quotes its argument?"
  (memq sbl '(quote function)))

(defun names--fboundp (sbl)
  "Is namespace+SBL a fboundp symbol?"
  (or (memq sbl names--fbound)
      (memq sbl names--macro)
      (and (names--keyword :global)
           (fboundp (names--prepend sbl)))))

(defun names--macrop (sbl)
  "Is namespace+SBL a fboundp symbol?"
  (or (memq sbl names--macro)
      (and (names--keyword :global)
           (macrop (names--prepend sbl)))))

(defun names--keyword (keyword)
  "Was KEYWORD one of the keywords passed to the `namespace' macro?"
  (memq keyword names--keywords))

(defun names--boundp (sbl)
  "Is namespace+SBL a boundp symbol?
If SBL has a let binding, that takes precendence so this also
returns nil."
  (and (null (memq sbl names--local-vars))
       (or (memq sbl names--bound)
           (and (names--keyword :global)
                (boundp (names--prepend sbl))))))

;;; This is calling edebug even on `when' and `unless'
(defun names--args-of-function-or-macro (name args macro)
  "Check whether NAME is a function or a macro, and handle ARGS accordingly."
  (if macro
      (cl-case (names--get-edebug-spec name)
        ;; Macros where we evaluate all arguments are like functions.
        ((t) (names--args-of-function-or-macro name args nil))
        ;; Macros where nothing is evaluated we can just return.
        (0 (cons name args))
        ;; Other macros are complicated. Ask edebug for help.
        (t (names--macro-args-using-edebug (cons name args))))
    ;; We just convert the arguments of functions.
    (cons name (mapcar 'names-convert-form args))))

(defun names--get-edebug-spec (name)
  "Get 'edebug-form-spec property of symbol NAME."
  ;; Get the spec of symbol resolving all indirection.
  (let ((spec nil)
        (indirect name))
    (while (progn
             (and (symbolp indirect)
                  (setq indirect
                        (function-get indirect 'edebug-form-spec 'macro))))
      ;; (edebug-trace "indirection: %s" edebug-form-spec)
      (setq spec indirect))
    spec))

(defvar names--is-inside-macro nil 
  "Auxiliary var used in `names--macro-args-using-edebug'.")

(defun names--macro-args-using-edebug (form)
  "Namespace the arguments of macro FORM by hacking into edebug.
This takes advantage of the fact that macros (should) declare a
`debug' specification which tells us which arguments are actually
lisp forms.

Ideally, we would read this specification ourselves and see how
it matches (cdr FORM), but that would take a lot of work and
we'd be reimplementing something that edebug already does
phenomenally. So we hack into edebug instead."
  (require 'edebug)
  (require 'noflet)
  (condition-case nil
      (with-temp-buffer
        (pp form 'insert)
        (goto-char (point-min))
        (let ((edebug-all-forms t)
              (edebug-all-defs t)
              (names--is-inside-macro form))
          (noflet ((message
                    (&rest _)
                    (if (names--keyword :verbose)
                        (apply this-fn _)
                      (apply 'format _)))
                   (edebug-form (cursor) (names--edebug-form cursor))
                   (edebug-make-enter-wrapper
                    (forms)
                    (setq edebug-def-name
                          (or edebug-def-name
                              edebug-old-def-name
                              (cl-gensym "names-edebug-anon")))
                    (cons 'progn forms)))
            (edebug-read-top-level-form))))
    (invalid-read-syntax
     (names--warn "Couldn't namespace this macro using its (debug ...) declaration: %s"
                   form)
     form)))

(defun names--edebug-form (cursor)
  "Parse form given by CURSOR using edebug, and namespace it if necessary."
  (require 'edebug)
  ;; Return the instrumented form for the following form.
  ;; Add the point offsets to the edebug-offset-list for the form.
  (let* ((form (edebug-top-element-required cursor "Expected form"))
         (offset (edebug-top-offset cursor))
         ;; This variable equals the current `names--edebug-form' depth.

         ;; We don't want to convert the entire form that was passed
         ;; to `names--macro-args-using-edebug', since the head of
         ;; that was already converted and it would lead to an
         ;; infinite loop.
         ;; So we check for (equal names--is-inside-macro form)

         ;; We DO want to convert the arguments that edebug identifies
         ;; as forms (level-1).
         
         ;; We also don't want to do anything once we're inside these
         ;; level-1 arguments (>= level 2), because that will already
         ;; be done by our own recursion when we call
         ;; `names-convert-form' on the level-1 forms.
         ;; So we check for (equal names--is-inside-macro t)
         
         (func (if (or (equal names--is-inside-macro t)
                       (equal names--is-inside-macro form))
                   'identity 'names-convert-form))
         (names--is-inside-macro
          (if (eq func 'names-convert-form)
              t names--is-inside-macro)))
    (names--message " [Edebug] ran into this: %S" form)
    (prog1
        (cond
         ((consp form) ;; The first offset for a list form is for the list form itself.
          (let* ((head (car form))
                 (spec (and (symbolp head) (get-edebug-spec head)))
                 (new-cursor (edebug-new-cursor form offset)))
            ;; Find out if this is a defining form from first symbol.
            ;; An indirect spec would not work here, yet.
            (if (and (consp spec) (eq '&define (car spec)))
                (edebug-defining-form
                 new-cursor
                 (car offset) ;; before the form
                 (edebug-after-offset cursor)
                 (cons (symbol-name head) (cdr spec)))
              ;; Wrap a regular form.
              (funcall func (edebug-list-form new-cursor)))))

         ((symbolp form)
          (funcall func form))

         ;; Anything else is self-evaluating.
         (t form))
      (edebug-move-cursor cursor))))


;;; ---------------------------------------------------------------
;;; Interpreting keywords passed to the main macro.
(defun names--handle-keyword (body)
  "Call the function that handles the keyword at the car of BODY.
The function must be named `names--keyword-KEY' (including the
colon), and must return whatever information is to be stored in
`names--keywords'. Usually, this information is at least the
keyword itself.

The car of BODY is the keyword itself. It will be popped later,
so the function generally shouldn't do that. For simple keywords,
the function can simply be an alias for `car'.

However, if the keyword takes one or more arguments, then this
function should indeed pop the car of BODY that many times."
  (let ((func (intern (format "names--keyword-%s" (car body)))))
    (if (fboundp func)
        (funcall func body)
      (error "[names] Keyword %s not recognized" (car body)))))

(defun names--keyword-:protection (body)
  "Return a cons with car and cadr of BODY and pop car."
  (let ((kw (car body))
        (val (symbol-name (cadr body))))
    (cl-assert (stringp val))
    (setq body (cdr body))
    (setq names--protection
          (format "\\`%s" (regexp-quote val)))
    (cons kw val)))

(defalias 'names--keyword-:let-vars 'car
  "The :let-vars keyword indicates variables assigned in let-bind are candidates for namespacing.")

(defalias 'names--keyword-:verbose 'car
  "The :verbose keyword causes a message to be called on each special form.")

(defalias 'names--keyword-:global 'car
  "The :global keyword is used to accept namespaced names from outside current namespace definition.
It will also be used when we implement something similar to
`eval-defun'." )

(defalias 'names--keyword-:assume-var-quote 'car
  "The :assume-var-quote keyword indicates symbols quoted with `quote' should be considered variable names." )

(defalias 'names--keyword-:dont-assume-function-quote 'car
  "The :dont-assume-function-quote keyword indicates symbols quoted with `function' should NOT be considered function names." )


;;; ---------------------------------------------------------------
;;; Interpreting the actual forms found in BODY of the main macro.
;;
;; This is where the heavy work is done.
;;
;; If you'd like to implement support for some special form, simply
;; define a function called `names--convert-FORM-NAME' along the
;; lines of the functions defined below. It will be automatically used
;; whenever that form is found.
(defvar names--name-already-prefixed nil
  "Whether some outer function already prefixed the name of the current defalias.")

(defun names--convert-defalias (form)
  "Special treatment for `defalias' FORM."
  (let ((dont-prefix names--name-already-prefixed))
    (setq names--name-already-prefixed nil)
    (list
     (car form)
     (if dont-prefix
         (cadr form)
       (let ((name (eval (cadr form)))) ;;ignore-errors
         (add-to-list 'names--fbound name)
         (list 'quote (names--prepend name))))
     (names-convert-form (cadr (cdr form))))))

;;; Defun, defmacro, and defsubst macros are pretty predictable. So we
;;; expand them and handle them like defaliases, instead of handling
;;; as general macros.
(defun names--convert-defmacro (form)
  "Special treatment for `defmacro' FORM."
  (let* ((names--name-already-prefixed t)
         (name (cadr form))
         (spaced-name (names--prepend name))
         decl)
    (add-to-list 'names--macro name)
    (add-to-list 'names--fbound name)
    ;; Set the macros debug spec if possible. It will be relevant on
    ;; the next run.
    (when (setq decl (ignore-errors (cond
                       ((eq (car-safe (nth 3 form)) 'declare)
                        (nth 3 form))
                       ((and (stringp (nth 3 form))
                             (eq (car-safe (nth 4 form)) 'declare))
                        (nth 4 form))
                       (t nil))))
      (setq decl (car (cdr-safe (assoc 'debug (cdr decl)))))
      (when decl (put spaced-name 'edebug-form-spec decl)))
    ;; Then convert the macro as a defalias.
    (names-convert-form
     (macroexpand
      (cons
       (car form)
       (cons spaced-name (cddr form)))))))
(defalias 'names--convert-defmacro* 'names--convert-defmacro)

(defun names--convert-defvar (form &optional dont-add)
  "Special treatment for `defvar' FORM."
  (let ((name (cadr form)))
    (unless dont-add
      (add-to-list 'names--bound name))
    (append
     (list
      (car form)
      (names--prepend name))
     (mapcar 'names-convert-form (cdr (cdr form))))))

(defalias 'names--convert-defconst 'names--convert-defvar
  "Special treatment for `defconst' FORM.")
(defalias 'names--convert-defcustom 'names--convert-defvar
  "Special treatment for `defcustom' FORM.")

(defun names--convert-defvaralias (form)
  "Special treatment for `defvaralias' FORM."
  (let ((name (eval (cadr form)))
        (name2 (eval (cl-caddr form))))
    (add-to-list 'names--bound name)
    (append
     (list
      (car form)
      (list 'quote (names--prepend name))
      (list 'quote (names-convert-form name2)))
     (mapcar 'names-convert-form (cdr (cdr form))))))

(defun names--convert-custom-declare-variable (form)
  "Special treatment for `custom-declare-variable' FORM."
  (let ((name (eval (cadr form))) ;;ignore-errors
        (val (cl-caddr form)))
    (add-to-list 'names--bound name)
    (append
     (list
      (car form)
      (list 'quote (names--prepend name)) ;cadr
      ;; The DEFAULT argument is explicitly evaluated by
      ;; `custom-declare-variable', so it should be safe to namespace
      ;; even when quoted. Plus, we need to do this because
      ;; defcustom quotes this part.
      (if (names--quote-p (car-safe val))
          (list (car val) (names-convert-form (cadr val)))
        (names-convert-form val))
      (names-convert-form        (car (cdr (cdr (cdr form))))))
     (mapcar 'names-convert-form (cdr (cdr (cdr (cdr form))))))))

(defun names--convert-defface (form)
  "Special treatment for `defface' FORM.
Identical to defvar, just doesn't add the symbol to the boundp
list."
  (names--convert-defvar form :dont-add))

(defun names--convert-define-derived-mode (form)
  "Special treatment for `define-derived-mode' FORM."
  (let ((name (cadr form)))
    (add-to-list 'names--fbound name)
    (add-to-list 'names--bound name)
    (add-to-list 'names--bound
                 (intern (format "%s-map" name)))
    (add-to-list 'names--bound
                 (intern (format "%s-hook" name)))
    (names--macro-args-using-edebug
     (cons
      (car form)
      (cons (names--prepend name)
            (cddr form))))))

(defun names--convert-define-minor-mode (form)
  "Special treatment for `define-minor-mode' FORM."
  (let ((name (cadr form))
        (keymap (nth 5 form)))
    ;; Register the mode name
    (add-to-list 'names--fbound name)
    (add-to-list 'names--bound name)
    (add-to-list 'names--bound (intern (format "%s-hook" name)))
    ;; Register the keymap
    (if (null (symbolp keymap))
        (add-to-list 'names--bound (intern (format "%s-map" name)))
      (when (setq keymap (names--remove-namespace keymap))
        (add-to-list 'names--bound keymap)))
    ;; And here we namespace it.
    (names--macro-args-using-edebug
     (cons
      (car form)
      (cons (names--prepend name)
            (cddr form))))))

(defun names--convert-quote (form)
  "Special treatment for `quote' FORM.
When FORM is (quote argument), argument is parsed for namespacing
only if it is a lambda form.

Anything else (a symbol or a general list) is too arbitrary to
be logically namespaced and will be preserved as-is.

Note, however, that the value of the NAME argument of a
\"definition-type\" forms is ALWAYS namespaced, regardless of
whether the form was a quote."
  (let ((kadr (cadr form))
        func)
    (if (eq (car-safe kadr) 'lambda)
        (list (car form) (names-convert-form kadr))
      (if (symbolp kadr)
          (cond
           ;; A symbol inside a function quote should be a function,
           ;; unless the user disabled that.
           ((and (eq (car form) 'function)
                 (null (names--keyword :dont-assume-function-quote)))
            (list 'function
                  (or (names--remove-protection kadr)
                      (if (names--fboundp kadr)
                          (names--prepend kadr)
                        kadr))))
           
           ;; A symbol inside a regular quote should be a function, if
           ;; the user asked for that.
           ((and (eq (car form) 'quote)
                 (names--keyword :assume-var-quote))
            (list 'quote
                  (or (names--remove-protection kadr)
                      (if (names--boundp kadr)
                          (names--prepend kadr)
                        kadr))))

           (t form))
        form))))

(defalias 'names--convert-function 'names--convert-quote)

(defun names--convert-\` (form)
  "Special treatment for backtick FORM.
Currently, we just return FORM without namespacing anything."
  form)

(defun names--convert-lambda (form)
  "Special treatment for `lambda' FORM."
  (let ((names--local-vars
         (append (names--vars-from-arglist (cadr form))
                 names--local-vars))
        (forms (cdr (cdr form))))
    (append
     (list (car form)
           (cadr form))
     (when (stringp (car forms))
       (prog1
           (list (car forms))
         (setq forms (cdr forms))))
     (when (eq 'interactive (car-safe (car forms)))
       (prog1
           (list (list (car (car forms))
                       (names-convert-form (cadr (car forms)))))
         (setq forms (cdr forms))))
     (progn
       ;; (message "%S" forms)
       (mapcar 'names-convert-form forms)))))

(defun names--vars-from-arglist (args)
  "Get a list of local variables from a generalized arglist ARGS."
  (cl-remove-if
   (lambda (x) (string-match "^&" (symbol-name x)))
   (mapcar (lambda (x) (or (cdr-safe (car-safe x)) (car-safe x) x))
           args)))

(defun names--convert-defun (form)
  "Special treatment for `defun' FORM."
  (let* ((name (cadr form)))
    (add-to-list 'names--fbound name)
    (cons (car form)
          (names--convert-lambda
           (cons (names--prepend name) (cddr form))))))
(defalias 'names--convert-defun* 'names--convert-defun)
(defalias 'names--convert-defsubst 'names--convert-defun)
(defalias 'names--convert-defsubst* 'names--convert-defun)

(defun names--let-var-convert-then-add (sym add)
  "Try to convert SYM if :let-vars is in use.
If ADD is non-nil, add resulting symbol to `names--local-vars'."
  (let ((name (if (names--keyword :let-vars)
                  (names-convert-form sym)
                sym)))
    (when add (add-to-list 'names--local-vars name))
    name))

(defun names--convert-let (form &optional star)
  "Special treatment for `let' FORM.
If STAR is non-nil, parse as a `let*'."
  (let* ((names--local-vars names--local-vars)
         (vars
          (mapcar
           (lambda (x)
             (if (car-safe x)
                 (list (names--let-var-convert-then-add (car x) star)
                       (names-convert-form (cadr x)))
               (names--let-var-convert-then-add x star)))
           (cadr form))))
    ;; Each var defined in a regular `let' only becomes protected after
    ;; all others have been defined.
    (unless star
      (setq names--local-vars
            (append
             (mapcar (lambda (x) (or (car-safe x) x)) vars)
             names--local-vars)))
    (append
     (list (car form) vars)
     (mapcar 'names-convert-form (cddr form)))))

(defun names--convert-let* (form)
  "Special treatment for `let' FORM."
  (names--convert-let form t))

(defun names--convert-condition-case (form)
  "Special treatment for `condition-case' FORM."
  (append
   (list
    (car form)
    (cadr form)
    (names-convert-form (cadr (cdr form))))
   (mapcar
    (lambda (x)
      (cons (car x)
            (mapcar 'names-convert-form (cdr x))))
    (cddr (cdr form)))))

(provide 'names)

;;; names.el ends here