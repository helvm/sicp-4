; SICP exercise 4.76
;
; Our implementation of and as a series combination of queries (figure 4.5) is
; elegant, but it is inefficient because in processing the second query of the
; and we must scan the data base for each frame produced by the first query.
; If the data base has N elements, and a typical query produces a number of
; output frames proportional to N (say N/k), then scanning the data base for
; each frame produced by the first query will require N²/k calls to the
; pattern matcher. Another approach would be to process the two clauses of the
; and separately, then look for all pairs of output frames that are
; compatible. If each query produces N/k output frames, then this means that
; we must perform N²/k² compatibility checks -- a factor of k fewer than the
; number of matches required in our current method.
;
; Devise an implementation of and that uses this strategy. You must implement
; a procedure that takes two frames as inputs, checks whether the bindings in
; the frames are compatible, and, if so, produces a frame that merges the two
; sets of bindings. This operation is similar to unification.

; The implementation is below. It has its disadvantages, though. First, the
; following query stops working:
;
; (and (supervisor ?x (Bitdiddle Ben))
;      (not (job ?x (computer programmer))))
;
; The reason is that (not (job ?x (computer programmer))) results to the empty
; stream of frames.
;
; There is another issue, which is illustrated in the outranked-by rule:
;
; (rule (outranked-by ?staff-person ?boss)
;       (or (supervisor ?staff-person ?boss)
;           (and (supervisor ?staff-person ?middle-manager)
;                (outranked-by ?middle-manager ?boss))))
;
; In this case, outranked-by results to an infinte loop, since
;
; (outranked-by ?staff-person ?boss)
;
; calls directly
;
; (outranked-by ?middle-manager ?boss)
;
; and all frames (not just the reduced set of frames from the previous
; conjunct.

#lang racket
(provide (all-defined-out))

; The Driver Loop and Instantiation
(define input-prompt ";;; Query input:")
(define output-prompt ";;; Query output:")
(define (query-driver-loop)
  (prompt-for-input input-prompt)
  (let ((q (query-syntax-process (read))))
    (cond ((assertion-to-be-added? q)
           (add-rule-or-assertion! (add-assertion-body q))
           (newline)
           (display "Assertion added to data base.")
           (query-driver-loop))
          (else
           (newline)
           (display output-prompt)
           (display-stream
            (stream-map
             (lambda (frame)
               (instantiate-exp q
                                frame
                                (lambda (v f) (contract-question-mark v))))
             (qeval q (singleton-stream '()))))
           (query-driver-loop)))))

(define (instantiate-exp exp frame unbound-var-handler)
  (define (copy exp)
    (cond ((var? exp)
           (let ((binding (binding-in-frame exp frame)))
             (if binding
                 (copy (binding-value binding))
                 (unbound-var-handler exp frame))))
          ((pair? exp)
           (cons (copy (car exp)) (copy (cdr exp))))
          (else exp)))
  (copy exp))

(define (prompt-for-input string)
  (newline) (newline) (display string) (newline))

(define (display-stream stream)
  (unless (stream-empty? stream)
    (newline)
    (display (stream-first stream))
    (display-stream (stream-rest stream))))

; The Evaluator

(define (qeval query frame-stream)
  (let ((qproc (get (type query) 'qeval)))
    (if qproc
        (qproc (contents query) frame-stream)
        (simple-query query frame-stream))))

;; Initialize namespace from client code.
;; This because, eval in racket (non-REPL) cannot see the bindings from the context where it is called.
;; (eval '>) success in REPL, but failed in non-REPL
;; See https://docs.racket-lang.org/guide/eval.html
;;
;; lisp-value will use operator eg:
;; (and (salary ?person ?amount) (lisp-value > ?amount 30000)) ;
;; (apply (eval '< ns) (list 1 2))
(define (ns-initialize ns0)
  (set! ns ns0))

(define (ns-finalize)
  (set! ns '()))

(define ns '())

(define (execute exp)
  (apply (eval (predicate exp) ns)
         (args exp)))

;; Exercise 4.71 delay
(define (simple-query query-pattern frame-stream)
  (stream-flatmap
   (lambda (frame)
     (stream-append
      (find-assertions query-pattern frame)
      (apply-rules query-pattern frame)))
   frame-stream))

(define (conjoin conjuncts frame-stream)
  (if (empty-conjunction? conjuncts)
      frame-stream
      (conjoin (rest-conjuncts conjuncts)
               (qeval (first-conjunct conjuncts)
                      frame-stream))))

;; Exercise 4.76
(define (merge-frames frame1 frame2)
  (cond ((null? frame1) frame2)
        ((eq? 'failed frame2) 'failed)
        (else
         (let ((var (binding-variable (car frame1)))
               (val (binding-value (car frame1))))
           (let ((extension (extend-if-possible var val frame2)))
             (merge-frames (cdr frame1) extension))))))

(define (conjoin-frame-streams stream1 stream2)
  (stream-flatmap
   (lambda (frame1)
     (stream-filter
      (lambda (frame) (not (eq? frame 'failed)))
      (stream-map
       (lambda (frame2) (merge-frames frame1 frame2))
       stream2)))
   stream1))

(define (faster-conjoin conjuncts frame-stream)
  (if (empty-conjunction? conjuncts)
      frame-stream
      (conjoin-frame-streams
       (qeval (first-conjunct conjuncts) frame-stream)
       (conjoin (rest-conjuncts conjuncts) frame-stream))))

;; Exercise 4.71 delay
(define (disjoin disjuncts frame-stream)
  (if (empty-disjunction? disjuncts)
      empty-stream
      (interleave (qeval (first-disjunct disjuncts) frame-stream)
                  (disjoin (rest-disjuncts disjuncts)
                           frame-stream))))

(define (negate operands frame-stream)
  (stream-flatmap
   (lambda (frame)
     (if (stream-empty? (qeval (negated-query operands) (singleton-stream frame)))
         (singleton-stream frame)
         empty-stream))
   frame-stream))

(define (lisp-value call frame-stream)
  (stream-flatmap
   (lambda (frame)
     (if (execute
          (instantiate-exp call
                           frame
                           (lambda (v f) (error "Unknown pat var -- LISP-VALUE" v))))
         (singleton-stream frame)
         empty-stream))
   frame-stream))

(define (always-true ignore frame-stream)
  frame-stream)

; Finding Assertions by Pattern Matching

(define (find-assertions pattern frame)
  (stream-flatmap (lambda (datum) (check-an-assertion datum pattern frame))
                  (fetch-assertions pattern frame)))

(define (check-an-assertion assertion query-pat query-frame)
  (let ((match-result (pattern-match query-pat assertion query-frame)))
    (if (eq? match-result 'failed)
        empty-stream
        (singleton-stream match-result))))

(define (pattern-match pat dat frame)
  (cond ((eq? frame 'failed) 'failed)
        ((equal? pat dat) frame)
        ((var? pat) (extend-if-consistent pat dat frame))
        ((and (pair? pat) (pair? dat))
         (pattern-match (cdr pat)
                        (cdr dat)
                        (pattern-match (car pat)
                                       (car dat)
                                       frame)))
        (else 'failed)))

(define (extend-if-consistent var dat frame)
  (let ((binding (binding-in-frame var frame)))
    (if binding
        (pattern-match (binding-value binding) dat frame)
        (extend var dat frame))))

; Rules and Unification

(define (apply-rules pattern frame)
  (stream-flatmap (lambda (rule) (apply-a-rule rule pattern frame))
                  (fetch-rules pattern frame)))

(define (apply-a-rule rule query-pattern query-frame)
  (let ((clean-rule (rename-variables-in rule)))
    (let ((unify-result (unify-match query-pattern
                                     (conclusion clean-rule)
                                     query-frame)))
      (if (eq? unify-result 'failed)
          empty-stream
          (qeval (rule-body clean-rule)
                 (singleton-stream unify-result))))))

(define (rename-variables-in rule)
  (let ((rule-application-id (new-rule-application-id)))
    (define (tree-walk exp)
      (cond ((var? exp)
             (make-new-variable exp rule-application-id))
            ((pair? exp)
             (cons (tree-walk (car exp))
                   (tree-walk (cdr exp))))
            (else exp)))
    (tree-walk rule)))

(define (unify-match p1 p2 frame)
  (cond ((eq? frame 'failed) 'failed)
        ((equal? p1 p2) frame)
        ((var? p1) (extend-if-possible p1 p2 frame))
        ((var? p2) (extend-if-possible p2 p1 frame)) ; ***
        ((and (pair? p1) (pair? p2))
         ;; The form is very similar to pattern-match and "match" in ../../../2/simplifier
         (unify-match (cdr p1)
                      (cdr p2)
                      (unify-match (car p1)
                                   (car p2)
                                   frame)))
        (else 'failed)))

(define (extend-if-possible var val frame)
  (let ((binding (binding-in-frame var frame)))
    (cond (binding
           (unify-match (binding-value binding) val frame))
          ((var? val)                           ; ***
           (let ((binding (binding-in-frame val frame)))
             (if binding
                 (unify-match var (binding-value binding) frame)
                 (extend var val frame))))
          ((depends-on? val var frame) 'failed) ; ***
          (else (extend var val frame)))))

(define (depends-on? exp var frame)
  (define (tree-walk e)
    (cond ((var? e)
           (if (equal? var e)
               true
               (let ((b (binding-in-frame e frame)))
                 (if b
                     (tree-walk (binding-value b))
                     false))))
          ((pair? e)
           (or (tree-walk (car e))
               (tree-walk (cdr e))))
          (else false)))
  (let ((result (tree-walk exp)))
    (if result
        (println "depends-on")
        'ok)
    result
    )
  )

; Maintaining the Data Base

(define THE-ASSERTIONS '())
(define (fetch-assertions pattern frame)
  (if (use-index? pattern)
      (get-indexed-assertions pattern)
      (get-all-assertions)))
(define (get-all-assertions)
  (reverse-list->stream THE-ASSERTIONS))
(define (get-indexed-assertions pattern)
  (reverse-list->stream
   (get-list (index-key-of pattern) 'assertion-list)))

(define THE-RULES '())
(define (fetch-rules pattern frame)
  (if (use-index? pattern)
      (get-indexed-rules pattern)
      (get-all-rules)))
(define (get-all-rules)
  (reverse-list->stream THE-RULES))
(define (get-indexed-rules pattern)
  (reverse-list->stream
   (append
    (get-list '? 'rule-list)
    (get-list (index-key-of pattern) 'rule-list))))

(define (add-rule-or-assertion! assertion)
  (if (rule? assertion)
      (add-rule! assertion)
      (add-assertion! assertion)))

(define (add-assertion! assertion)
  (store-assertion-in-index assertion)
  (let ((old-assertions THE-ASSERTIONS))
    (set! THE-ASSERTIONS (cons assertion old-assertions))
    'ok))

(define (add-rule! rule)
  (store-rule-in-index rule)
  (let ((old-rules THE-RULES))
    (set! THE-RULES (cons rule old-rules))
    'ok))

(define (store-assertion-in-index assertion)
  (when (indexable? assertion)
    (let ((key (index-key-of assertion)))
      (let ((current-assertion-list (get-list key 'assertion-list)))
        (put key
             'assertion-list
             (cons assertion current-assertion-list))))))

(define (store-rule-in-index rule)
  (let ((pattern (conclusion rule)))
    (when (indexable? pattern)
      (let ((key (index-key-of pattern)))
        (let ((current-rule-list (get-list key 'rule-list)))
          (put key
               'rule-list
               (cons rule current-rule-list)))))))

(define (indexable? pattern)
  (or (constant-symbol? (car pattern))
      (var? (car pattern))))

(define (index-key-of pattern)
  (let ((key (car pattern)))
    (if (var? key) '? key)))

(define (use-index? pattern)
  (constant-symbol? (car pattern)))

(define (list->stream items)
  (if (null? items)
      empty-stream
      (stream-cons (car items)
                   (list->stream (cdr items)))))

(define (reverse-list->stream items)
  (list->stream (reverse items)))

(define (get-list key1 key2)
  (let ((s (get key1 key2)))
    (if s s '())))

; Operator table

(define table (make-hash))

(define (put op type item)
  (hash-set! table (list op type) item))

(define (get op type)
  (hash-ref table (list op type) #f))

; Stream Operations

(define (interleave s1 s2)
  (if (stream-empty? s1)
      s2
      (stream-cons
       (stream-first s1)
       (interleave s2 (stream-rest s1)))))

(define (stream-flatmap proc s)
  (flatten-stream (stream-map proc s)))

;; Exercise 4.73 delay
(define (flatten-stream stream)
  (if (stream-empty? stream)
      empty-stream
      (interleave (stream-first stream)
                  (flatten-stream (stream-rest stream)))))

(define (singleton-stream x)
  (stream-cons x empty-stream))

; Query Syntax Procedures

(define (type exp)
  (if (pair? exp)
      (car exp)
      (error "Unknown expression TYPE" exp)))

(define (contents exp)
  (if (pair? exp)
      (cdr exp)
      (error "Unknown expression CONTENTS" exp)))

(define (assertion-to-be-added? exp) (eq? (type exp) 'assert!))
(define (add-assertion-body exp) (car (contents exp)))

(define (empty-conjunction? exps) (null? exps))
(define (first-conjunct exps) (car exps))
(define (rest-conjuncts exps) (cdr exps))
(define (empty-disjunction? exps) (null? exps))
(define (first-disjunct exps) (car exps))
(define (rest-disjuncts exps) (cdr exps))
(define (negated-query exps) (car exps))
(define (predicate exps) (car exps))
(define (args exps) (cdr exps))

(define (rule? statement) (tagged-list? statement 'rule))
(define (conclusion rule) (cadr rule))
(define (rule-body rule) (if (null? (cddr rule)) '(always-true) (caddr rule)))

(define (query-syntax-process exp)
  (map-over-symbols expand-question-mark exp))

(define (map-over-symbols proc exp)
  (cond ((pair? exp)
         (cons (map-over-symbols proc (car exp))
               (map-over-symbols proc (cdr exp))))
        ((symbol? exp) (proc exp))
        (else exp)))

(define (expand-question-mark symbol)
  (let ((chars (symbol->string symbol)))
    (if (string=? (substring chars 0 1) "?")
        (list '?
              (string->symbol
               (substring chars 1 (string-length chars))))
        symbol)))

(define (var? exp) (tagged-list? exp '?))
(define (constant-symbol? exp) (symbol? exp))

(define rule-counter 0)
(define (new-rule-application-id)
  (set! rule-counter (+ 1 rule-counter))
  rule-counter)
(define (make-new-variable var rule-application-id)
  (cons '? (cons rule-application-id (cdr var))))

(define (contract-question-mark variable)
  (string->symbol
   (string-append "?"
                  (if (number? (cadr variable))
                      (string-append (symbol->string (caddr variable))
                                     "-"
                                     (number->string (cadr variable)))
                      (symbol->string (cadr variable))))))

(define (tagged-list? exp tag)
  (and (pair? exp)
       (eq? (car exp) tag)))

; Frames and Bindings

(define (make-binding variable value)
  (cons variable value))
(define (binding-variable binding)
  (car binding))
(define (binding-value binding)
  (cdr binding))
(define (binding-in-frame variable frame)
  (assoc variable frame))
(define (extend variable value frame)
  (cons (make-binding variable value) frame))

; Reseting the state

(define (reset-state!)
  (set! table (make-hash))
  (set! rule-counter 0)
  (set! THE-ASSERTIONS '())
  (set! THE-RULES '())

  (put 'and 'qeval faster-conjoin)
  (put 'or 'qeval disjoin)
  (put 'not 'qeval negate)
  (put 'lisp-value 'qeval lisp-value)
  (put 'always-true 'qeval always-true))

(reset-state!)


