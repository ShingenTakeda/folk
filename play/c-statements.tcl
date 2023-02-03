source "lib/c.tcl"

set cc [c create]

namespace eval statement {
    $cc include <string.h>
    $cc include <stdlib.h>

    $cc typedef uint32_t statement_id_t
    $cc typedef uint32_t match_id_t
    $cc typedef {struct trie} trie_t
    $cc enum edge_type_t {
        PARENT,
        CHILD
    }
    $cc struct match_t {
        size_t n_edges;
        struct {
            edge_type_t type;
            statement_id_t statementId;
        } edges[];
    }
    $cc struct statement_t {
        Tcl_Obj* clause;

        size_t n_edges;
        struct {
            edge_type_t type;
            match_id_t matchId;
        } edges;
    }

    $cc proc createImpl {Tcl_Obj* clause
                         size_t nchildMatc parent_set_t[8] setsOfParents} statement_t* {
        size_t size = sizeof(statement_t) + 10*sizeof(child_t);
        statement_t* ret = ckalloc(size); memset(ret, 0, size);

        ret->clause = clause; Tcl_IncrRefCount(ret->clause);

        if (nchildMatches > 8) { exit(1); }
        memcpy(ret->setsOfParents, setsOfParents, nsetsOfParents*sizeof(parent_set_t));

        ret->nchildren = 10;

        return ret;
    }
}

namespace eval Statements {
    $cc code {
        size_t nstatements;
        statement_t* statements[32768];
        statement_id_t nextStatementId = 1;
        trie_t* statementClauseToId;
    }
    $cc proc add {Tcl_Interp* interp
                  Tcl_Obj* clause parent_set_t parents} child_t {
        // Empty set of parents = an assertion

        // Is this clause already present among the existing statements?
        Tcl_Obj* ids = lookup(interp, statementClauseToId, clause);
        int idslen; Tcl_ListObjLength(interp, ids, &idsLen);
        if (idslen == 1) {
            Tcl_Obj* idobj; Tcl_ListObjIndex(interp, ids, 0, &idobj);
            int id; Tcl_GetIntFromObj(interp, idobj, &id);

            statements[id].setsOfParents[newSetOfParentsId] = parents;

            return { .id = id, .parentSet = parents };

        } else if (idslen == 0) {
            int id = nextStatementId++;
            statement_t stmt = create(clause, 1, parents, 0, NULL);
            statements[id] = stmt;

            int objc; Tcl_Obj** objv; Tcl_ListObjGetElements(interp, clause, &objc, &objv);
            trieAddImpl(&statementClauseToId, objc, objv, id);

            return { .id = id, .parentSet = parents };

        } else {
            // error WTF
        }
    }
}

$cc compile
source "lib/c.tcl"

set cc [c create]

namespace eval statement {
    $cc include <string.h>
    $cc include <stdlib.h>

    $cc typedef uint32_t statement_id_t
    $cc typedef {struct trie} trie_t
    $cc struct parent_set_t {
        statement_id_t parent[2];
    }
    $cc struct child_t {
        statement_id_t id;
        parent_set_t parentSet;
    }
    $cc struct statement_t {
        Tcl_Obj* clause;
        parent_set_t setsOfParents[8];

        size_t nchildren;
        child_t children[];
    }

    $cc proc createImpl {Tcl_Obj* clause
                         size_t nsetsOfParents parent_set_t[8] setsOfParents} statement_t* {
        size_t size = sizeof(statement_t) + 10*sizeof(child_t);
        statement_t* ret = ckalloc(size); memset(ret, 0, size);

        ret->clause = clause; Tcl_IncrRefCount(ret->clause);

        if (nsetsOfParents > 8) { exit(1); }
        memcpy(ret->setsOfParents, setsOfParents, nsetsOfParents*sizeof(parent_set_t));

        ret->nchildren = 10;

        return ret;
    }
}

namespace eval Statements {
    $cc code {
        size_t nstatements;
        statement_t* statements[32768];
        statement_id_t nextStatementId = 1;
        trie_t* statementClauseToId;
    }
    $cc proc add {Tcl_Interp* interp
                  Tcl_Obj* clause parent_set_t parents} child_t {
        // Empty set of parents = an assertion

        // Is this clause already present among the existing statements?
        Tcl_Obj* ids = lookup(interp, statementClauseToId, clause);
        int idslen; Tcl_ListObjLength(interp, ids, &idsLen);
        if (idslen == 1) {
            Tcl_Obj* idobj; Tcl_ListObjIndex(interp, ids, 0, &idobj);
            int id; Tcl_GetIntFromObj(interp, idobj, &id);

            statements[id].setsOfParents[newSetOfParentsId] = parents;

            return { .id = id, .parentSet = parents };

        } else if (idslen == 0) {
            int id = nextStatementId++;
            statement_t stmt = create(clause, 1, parents, 0, NULL);
            statements[id] = stmt;

            int objc; Tcl_Obj** objv; Tcl_ListObjGetElements(interp, clause, &objc, &objv);
            trieAddImpl(&statementClauseToId, objc, objv, id);

            return { .id = id, .parentSet = parents };

        } else {
            // error WTF
        }
    }
}

$cc compile